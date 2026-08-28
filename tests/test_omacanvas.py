import unittest
from datetime import datetime, timezone
import os
import stat
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch
from urllib.request import Request

sys.path.insert(0, str(Path(__file__).parents[1]))
from importlib.machinery import SourceFileLoader

module = SourceFileLoader("omacanvas", str(Path(__file__).parents[1] / "omacanvas")).load_module()


class FakeClient:
    base_url = "https://canvas.test/"

    def get_all(self, path, params=None):
        if path == "api/v1/users/self/courses":
            return [{"id": 1, "name": "Software Engineering", "course_code": "CSC3400",
                     "enrollments": [{"type": "student", "computed_current_score": 95.5}]}]
        return [{"id": 2, "name": "In range", "due_at": "2026-09-01T15:00:00Z",
                 "submission": {"submitted_at": None}, "html_url": "https://canvas.test/a/2"},
                {"id": 3, "name": "Too late", "due_at": "2026-09-20T15:00:00Z", "submission": {}}]


class MixedRoleClient:
    base_url = "https://canvas.test/"

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


class FakeResponse:
    def __init__(self, payload, link=None, raw=None):
        self.raw = raw if raw is not None else module.json.dumps(payload).encode("utf-8")
        self.headers = {"Link": link} if link else {}

    def read(self, limit=-1):
        return self.raw if limit < 0 else self.raw[:limit]

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class FakeOpener:
    def __init__(self, *responses):
        self.responses = list(responses)

    def open(self, _request, timeout=None):
        if not self.responses:
            raise AssertionError("Unexpected API request")
        return self.responses.pop(0)


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

    def test_sanitizes_canvas_text_for_ui_and_terminal_output(self):
        self.assertEqual(
            module.sanitize_text("&lt;img src='https://attacker.example/pixel'&gt;\x1b[31m"),
            "<img src='https://attacker.example/pixel'> [31m",
        )
        self.assertEqual(module.sanitize_text(None, "Untitled"), "Untitled")

    def test_validates_canvas_assignment_web_url(self):
        self.assertEqual(
            module.validated_canvas_web_url(
                "https://canvas.example.edu",
                "/courses/10/assignments/20",
            ),
            "https://canvas.example.edu/courses/10/assignments/20",
        )

    def test_rejects_external_or_unsafe_assignment_web_url(self):
        for value in (
            "https://attacker.example/collect",
            "http://canvas.example.edu/courses/10/assignments/20",
            "javascript:alert(1)",
            "https://canvas.example.edu/courses/10/assignments/20\nfile:///etc/passwd",
            None,
        ):
            with self.subTest(value=value):
                self.assertIsNone(
                    module.validated_canvas_web_url("https://canvas.example.edu", value)
                )

    def test_builds_canvas_course_web_url(self):
        self.assertEqual(
            module.canvas_course_web_url("https://canvas.example.edu", 12345),
            "https://canvas.example.edu/courses/12345",
        )

    def test_rejects_invalid_canvas_course_id_for_web_url(self):
        for value in (True, "", "../account", "12/assignments"):
            with self.subTest(value=value):
                self.assertIsNone(
                    module.canvas_course_web_url("https://canvas.example.edu", value)
                )

    def test_missing_credentials_return_none(self):
        with patch.dict(os.environ, {"CANVAS_API_KEY": "environment-token"}), \
             patch.object(module, "_keyring_token", return_value=None):
            self.assertIsNone(module.get_token("https://canvas.example.edu"))

    def test_environment_token_requires_explicit_opt_in(self):
        with patch.dict(os.environ, {"CANVAS_API_KEY": "from-environment"}), \
             patch.object(module, "_keyring_token") as keyring:
            self.assertEqual(
                module.get_token("https://canvas.example.edu", token_from_environment=True),
                "from-environment",
            )
            keyring.assert_not_called()

    def test_environment_token_does_not_override_scoped_keyring(self):
        with patch.dict(os.environ, {"CANVAS_API_KEY": "wrong-instance-token"}), \
             patch.object(module, "_keyring_token", return_value="scoped-token"):
            self.assertEqual(
                module.get_token("https://canvas.example.edu"),
                "scoped-token",
            )

    def test_keyring_lookup_is_scoped_to_canvas_url(self):
        completed = Mock(stdout="saved-token\n")
        with patch.object(module, "secret_tool_path", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run", return_value=completed) as run:
            self.assertEqual(module._keyring_token("https://canvas.example.edu/"), "saved-token")
            self.assertEqual(
                run.call_args.args[0],
                ["/usr/bin/secret-tool", "lookup", "service", "omacanvas", "base_url", "https://canvas.example.edu"],
            )

    def test_keyring_failure_has_actionable_error(self):
        with patch.object(module, "secret_tool_path", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run", side_effect=OSError("keyring unavailable")):
            with self.assertRaisesRegex(RuntimeError, "system keyring"):
                module._keyring_token("https://canvas.example.edu")

    def test_save_token_is_scoped_to_canvas_url(self):
        with patch.object(module, "secret_tool_path", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run") as run:
            module.save_token("https://canvas.example.edu/", "secret-token")
            self.assertEqual(
                run.call_args.args[0],
                ["/usr/bin/secret-tool", "store", "--label=Omacanvas API token (canvas.example.edu)",
                 "service", "omacanvas", "base_url", "https://canvas.example.edu"],
            )
            self.assertEqual(run.call_args.kwargs["input"], "secret-token\n")

    def test_save_token_failure_has_actionable_error(self):
        with patch.object(module, "secret_tool_path", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run", side_effect=OSError("keyring unavailable")):
            with self.assertRaisesRegex(RuntimeError, "Could not save"):
                module.save_token("https://canvas.example.edu", "secret-token")

    def test_clear_token_checks_keyring_exit_status(self):
        with patch.object(module, "secret_tool_path", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run") as run:
            module.clear_token("https://canvas.example.edu")
            self.assertTrue(run.call_args.kwargs["check"])
            self.assertEqual(run.call_args.kwargs["timeout"], 10)

    def test_clear_token_failure_is_not_reported_as_success(self):
        failure = module.subprocess.CalledProcessError(1, ["secret-tool", "clear"])
        with patch.object(module, "secret_tool_path", return_value="/usr/bin/secret-tool"), \
             patch.object(module.subprocess, "run", side_effect=failure):
            with self.assertRaisesRegex(RuntimeError, "Could not remove"):
                module.clear_token("https://canvas.example.edu")

    def test_collects_only_assignments_in_window(self):
        data = module.collect(FakeClient(), 14, datetime(2026, 8, 27, tzinfo=timezone.utc))
        self.assertEqual(len(data["courses"]), 1)
        self.assertEqual([a["name"] for a in data["courses"][0]["assignments"]], ["In range"])
        self.assertEqual(
            data["courses"][0]["assignments"][0]["html_url"],
            "https://canvas.test/a/2",
        )
        self.assertEqual(
            data["courses"][0]["html_url"],
            "https://canvas.test/courses/1",
        )

    def test_next_link(self):
        self.assertEqual(module._next_link('<https://canvas.test/p2>; rel="next"'), "https://canvas.test/p2")

    def test_accepts_same_origin_pagination_link(self):
        self.assertEqual(
            module._require_same_origin(
                "https://canvas.example.edu/",
                "https://canvas.example.edu/api/v1/courses?page=2",
            ),
            "https://canvas.example.edu/api/v1/courses?page=2",
        )

    def test_rejects_cross_origin_pagination_link(self):
        with self.assertRaisesRegex(module.CrossOriginRequestError, "outside"):
            module._require_same_origin(
                "https://canvas.example.edu/",
                "https://attacker.example/api/v1/courses?page=2",
            )

    def test_rejects_cross_origin_redirect_before_copying_headers(self):
        handler = module.SameOriginRedirectHandler("https://canvas.example.edu/")
        request = Request(
            "https://canvas.example.edu/api/v1/courses",
            headers={"Authorization": "Bearer secret-token"},
        )
        with self.assertRaises(module.CrossOriginRequestError):
            handler.redirect_request(
                request, None, 302, "Found", {},
                "https://attacker.example/collect",
            )

    def test_rejects_oversized_api_response(self):
        response = FakeResponse([], raw=b"[" + b" " * 20 + b"]")
        with patch.object(module, "MAX_RESPONSE_BYTES", 10):
            client = module.CanvasClient(
                "https://canvas.example.edu", "token",
                opener=FakeOpener(response), clock=lambda: 0,
            )
            with self.assertRaisesRegex(RuntimeError, "size limit"):
                client.get_all("api/v1/courses")

    def test_rejects_repeated_pagination_page(self):
        first_url = "https://canvas.example.edu/api/v1/courses"
        response = FakeResponse([], link=f'<{first_url}>; rel="next"')
        client = module.CanvasClient(
            "https://canvas.example.edu", "token",
            opener=FakeOpener(response), clock=lambda: 0,
        )
        with self.assertRaisesRegex(RuntimeError, "repeated"):
            client.get_all("api/v1/courses")

    def test_rejects_too_many_api_records(self):
        with patch.object(module, "MAX_RECORDS", 1):
            client = module.CanvasClient(
                "https://canvas.example.edu", "token",
                opener=FakeOpener(FakeResponse([{"id": 1}, {"id": 2}])),
                clock=lambda: 0,
            )
            with self.assertRaisesRegex(RuntimeError, "record limit"):
                client.get_all("api/v1/courses")

    def test_enforces_overall_fetch_deadline(self):
        times = iter((0, module.MAX_FETCH_SECONDS + 1))
        client = module.CanvasClient(
            "https://canvas.example.edu", "token",
            opener=FakeOpener(), clock=lambda: next(times),
        )
        with self.assertRaisesRegex(RuntimeError, "allowed duration"):
            client.get_all("api/v1/courses")

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

    def test_hidden_course_preferences_are_written_privately_and_atomically(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "omacanvas" / "hidden-courses.json"
            module.set_course_hidden(
                "https://canvas.example.edu", "20", True,
                "Orientation", "ORIENT", path,
            )

            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            self.assertEqual(list(path.parent.glob(".hidden-courses.json.*.tmp")), [])

    def test_rejects_symlinked_hidden_course_preferences(self):
        with TemporaryDirectory() as directory:
            target = Path(directory) / "target.json"
            target.write_text('{"version": 1, "instances": {}}', encoding="utf-8")
            path = Path(directory) / "hidden-courses.json"
            path.symlink_to(target)

            with self.assertRaisesRegex(RuntimeError, "symbolic link"):
                module.hidden_courses_for("https://canvas.example.edu", path)


if __name__ == "__main__":
    unittest.main()
