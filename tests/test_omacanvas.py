import unittest
from datetime import datetime, timezone
import os
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from importlib.machinery import SourceFileLoader

module = SourceFileLoader("omacanvas", str(Path(__file__).parents[1] / "omacanvas")).load_module()


class FakeClient:
    def get_all(self, path, params=None):
        if path == "api/v1/users/self/courses":
            return [{"id": 1, "name": "Software Engineering", "course_code": "CSC3400",
                     "enrollments": [{"type": "student", "computed_current_score": 95.5}]}]
        return [{"id": 2, "name": "In range", "due_at": "2026-09-01T15:00:00Z",
                 "submission": {"submitted_at": None}, "html_url": "https://canvas.test/a/2"},
                {"id": 3, "name": "Too late", "due_at": "2026-09-20T15:00:00Z", "submission": {}}]


class MixedRoleClient:
    def __init__(self):
        self.requested_paths = []
        self.requested_params = []

    def get_all(self, path, params=None):
        self.requested_paths.append(path)
        self.requested_params.append(params)
        if path == "api/v1/users/self/courses":
            return [
                {"id": 10, "name": "Course I Teach",
                 "enrollments": [{"type": "teacher"}]},
                {"id": 20, "name": "Course I Take",
                 "enrollments": [{"type": "StudentEnrollment", "computed_current_grade": "A"}]},
            ]
        return []


class CanvasTests(unittest.TestCase):
    def test_normalizes_canvas_url(self):
        self.assertEqual(
            module.normalize_instance_url(" HTTPS://Canvas.Example.EDU/ "),
            "https://canvas.example.edu",
        )

    def test_rejects_malformed_canvas_url(self):
        for value in (
            "canvas.example.edu",
            "not a url",
            "http://canvas.example.edu",
            "ftp://canvas.example.edu",
            "https://user:password@canvas.example.edu",
            "https://canvas.example.edu/courses/123",
            "https://canvas.example.edu?account=1",
            "https://canvas.example.edu#settings",
            "https://canvas.example.edu:invalid",
        ):
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                module.normalize_instance_url(value)

    def test_missing_credentials_return_none(self):
        with patch.dict(os.environ, {"CANVAS_API_KEY": ""}), \
             patch.object(module, "_keyring_token", return_value=None):
            self.assertIsNone(module.get_token("https://canvas.example.edu"))

    def test_environment_token_works_without_keyring(self):
        with patch.dict(os.environ, {"CANVAS_API_KEY": "from-environment"}), \
             patch.object(module, "_keyring_token") as keyring:
            self.assertEqual(
                module.get_token("https://canvas.example.edu"),
                "from-environment",
            )
            keyring.assert_not_called()

    def test_keyring_lookup_is_scoped_to_canvas_url(self):
        completed = Mock(stdout="saved-token\n")
        with patch.object(module, "shutil_which", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run", return_value=completed) as run:
            self.assertEqual(module._keyring_token("https://canvas.example.edu/"), "saved-token")
            self.assertEqual(
                run.call_args.args[0],
                ["secret-tool", "lookup", "service", "omacanvas", "base_url", "https://canvas.example.edu"],
            )

    def test_keyring_failure_has_actionable_error(self):
        with patch.object(module, "shutil_which", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run", side_effect=OSError("keyring unavailable")):
            with self.assertRaisesRegex(RuntimeError, "system keyring"):
                module._keyring_token("https://canvas.example.edu")

    def test_save_token_is_scoped_to_canvas_url(self):
        with patch.object(module, "shutil_which", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run") as run:
            module.save_token("https://canvas.example.edu/", "secret-token")
            self.assertEqual(
                run.call_args.args[0],
                ["secret-tool", "store", "--label=Omacanvas API token (canvas.example.edu)",
                 "service", "omacanvas", "base_url", "https://canvas.example.edu"],
            )
            self.assertEqual(run.call_args.kwargs["input"], "secret-token\n")

    def test_save_token_failure_has_actionable_error(self):
        with patch.object(module, "shutil_which", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run", side_effect=OSError("keyring unavailable")):
            with self.assertRaisesRegex(RuntimeError, "Could not save"):
                module.save_token("https://canvas.example.edu", "secret-token")

    def test_collects_only_assignments_in_window(self):
        data = module.collect(FakeClient(), 14, datetime(2026, 8, 27, tzinfo=timezone.utc))
        self.assertEqual(len(data["courses"]), 1)
        self.assertEqual([a["name"] for a in data["courses"][0]["assignments"]], ["In range"])

    def test_next_link(self):
        self.assertEqual(module._next_link('<https://canvas.test/p2>; rel="next"'), "https://canvas.test/p2")

    def test_excludes_teacher_only_courses_before_fetching_assignments(self):
        client = MixedRoleClient()
        data = module.collect(client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc))

        self.assertEqual([course["name"] for course in data["courses"]], ["Course I Take"])
        self.assertEqual(client.requested_params[0]["enrollment_type"], "student")
        self.assertNotIn("api/v1/courses/10/assignments", client.requested_paths)
        self.assertIn("api/v1/courses/20/assignments", client.requested_paths)

    def test_hidden_course_skips_assignment_request(self):
        client = MixedRoleClient()
        data = module.collect(
            client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc),
            hidden_course_ids={"20"},
        )

        self.assertEqual(data["courses"], [])
        self.assertEqual([course["id"] for course in data["hidden_courses"]], [20])
        self.assertNotIn("api/v1/courses/20/assignments", client.requested_paths)

    def test_hidden_course_preferences_are_scoped_by_canvas_url(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "hidden-courses.json"
            module.set_course_hidden(
                "https://canvas.example.edu/", "20", True,
                "Orientation", "ORIENT", path,
            )

            self.assertIn("20", module.hidden_courses_for("https://canvas.example.edu", path))
            self.assertEqual(module.hidden_courses_for("https://other.example.edu", path), {})

            module.set_course_hidden("https://canvas.example.edu", "20", False, path=path)
            self.assertEqual(module.hidden_courses_for("https://canvas.example.edu", path), {})


if __name__ == "__main__":
    unittest.main()
