import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.christopherhaynes33.omacanvas"
  ipcTarget: "io.github.christopherhaynes33.omacanvas"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: decodeURIComponent(
    String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string helperPath: pluginDir + "/omacanvas"
  readonly property string baseUrl: String(setting("baseUrl", "")).trim()
  readonly property string configurationMessage: "Set your Canvas URL in Setup › Plugins › Omacanvas, then save an API token for that URL."
  readonly property int days: boundedSetting("days", 14, 1, 60)
  readonly property int refreshSec: boundedSetting("refreshIntervalSec", 21600, 300, 86400)

  readonly property var paneNames: ["Overview", "Assignments", "Courses"]
  property int selectedPane: 0
  property bool cursorActive: false
  property string selectedCourseId: ""
  property var payload: ({ fetched_at: "", days: 14, courses: [], hidden_courses: [] })
  property string errorText: ""
  property string visibilityError: ""
  property bool loading: false
  property bool refreshAfterStatus: false
  property var pendingVisibilityCourse: null
  property bool pendingHiddenState: false
  property bool hiddenCoursesExpanded: false

  readonly property var courses: payload.courses || []
  readonly property var hiddenCourses: payload.hidden_courses || []
  readonly property var assignments: flattenAssignments(courses)
  readonly property var selectedCourse: findSelectedCourse()
  readonly property int selectedCourseIndex: findSelectedCourseIndex()
  readonly property int pendingCount: countAssignments(false)
  readonly property int submittedCount: assignments.length - pendingCount
  readonly property int urgentCount: {
    var total = 0
    var cutoff = Date.now() + 2 * 24 * 60 * 60 * 1000
    for (var i = 0; i < assignments.length; i++) {
      var due = new Date(assignments[i].due_at).getTime()
      if (!assignments[i].submitted && isFinite(due) && due <= cutoff) total++
    }
    return total
  }

  onHiddenCoursesChanged: if (hiddenCourses.length === 0) hiddenCoursesExpanded = false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function alpha(color, amount) { return Qt.rgba(color.r, color.g, color.b, amount) }

  function boundedSetting(key, fallback, minimum, maximum) {
    var value = Number(setting(key, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, Math.round(value)))
  }

  function flattenAssignments(courseList) {
    var rows = []
    for (var i = 0; i < courseList.length; i++) {
      var course = courseList[i]
      var courseAssignments = course.assignments || []
      for (var j = 0; j < courseAssignments.length; j++) {
        var source = courseAssignments[j]
        rows.push({
          id: source.id,
          name: source.name,
          due_at: source.due_at,
          submitted: source.submitted,
          html_url: source.html_url,
          course_id: course.id,
          course_name: course.name,
          course_code: course.code
        })
      }
    }
    rows.sort(function(a, b) {
      return new Date(a.due_at).getTime() - new Date(b.due_at).getTime()
    })
    return rows
  }

  function countAssignments(submitted) {
    var total = 0
    for (var i = 0; i < assignments.length; i++)
      if (!!assignments[i].submitted === submitted) total++
    return total
  }

  function findSelectedCourse() {
    for (var i = 0; i < courses.length; i++)
      if (String(courses[i].id) === selectedCourseId) return courses[i]
    return courses.length > 0 ? courses[0] : null
  }

  function findSelectedCourseIndex() {
    for (var i = 0; i < courses.length; i++)
      if (String(courses[i].id) === selectedCourseId) return i
    return courses.length > 0 ? 0 : -1
  }

  function ensureSelectedCourse() {
    if (courses.length === 0) {
      selectedCourseId = ""
      return
    }
    for (var i = 0; i < courses.length; i++)
      if (String(courses[i].id) === selectedCourseId) return
    selectedCourseId = String(courses[0].id)
  }

  function selectPane(index) {
    selectedPane = ((index % paneNames.length) + paneNames.length) % paneNames.length
    cursorActive = true
    if (panelFlick) panelFlick.contentY = 0
  }

  function selectCourseOffset(offset) {
    if (courses.length === 0) return
    var index = ((selectedCourseIndex + offset) % courses.length + courses.length) % courses.length
    selectedCourseId = String(courses[index].id)
    if (panelFlick) panelFlick.contentY = 0
  }

  function refreshNow() {
    if (statusProc.running) return
    if (baseUrl === "") {
      errorText = configurationMessage
      return
    }
    loading = true
    errorText = ""
    statusProc.running = true
  }

  function grade(course) {
    if (!course) return "No grade"
    if (course.current_grade !== null && course.current_grade !== undefined && course.current_grade !== "")
      return String(course.current_grade)
    if (course.current_score !== null && course.current_score !== undefined)
      return Number(course.current_score).toFixed(1) + "%"
    return "No grade"
  }

  function dueLabel(value) {
    var date = new Date(value)
    if (!isFinite(date.getTime())) return "No due date"
    return date.toLocaleString(Qt.locale(), "ddd MMM d, h:mm AP")
  }

  function fetchedLabel() {
    var date = new Date(payload.fetched_at || "")
    if (!isFinite(date.getTime())) return loading ? "REFRESHING" : "NOT YET UPDATED"
    return "UPDATED " + date.toLocaleString(Qt.locale(), "h:mm AP")
  }

  function elidedLabel(value, maximumLength) {
    var label = String(value || "").trim()
    if (label.length <= maximumLength) return label
    return label.substring(0, maximumLength - 1) + "…"
  }

  function courseLabel(course, index) {
    var code = String(course.code || "").trim()
    if (code !== "") return elidedLabel(code, 20)
    return elidedLabel(course.name || ("Course " + (index + 1)), 20)
  }

  function canvasItemUrl(item) {
    if (!item) return ""
    var candidate = String(item.html_url || "").trim()
    var origin = String(baseUrl || "").trim().replace(/\/+$/, "").toLowerCase()
    if (candidate === "" || origin === "") return ""
    return candidate.toLowerCase().indexOf(origin + "/") === 0 ? candidate : ""
  }

  function openAssignment(assignment) {
    var url = canvasItemUrl(assignment)
    if (url !== "") Qt.openUrlExternally(url)
  }

  function openCourse(course) {
    var url = canvasItemUrl(course)
    if (url !== "") Qt.openUrlExternally(url)
  }

  function setCourseVisibility(course, hidden) {
    if (!course || visibilityProc.running || baseUrl === "") return
    pendingVisibilityCourse = course
    pendingHiddenState = hidden
    visibilityError = ""
    var command = [
      helperPath, hidden ? "hide-course" : "unhide-course",
      String(course.id)
    ]
    if (hidden) {
      command.push("--course-name", String(course.name || ""))
      command.push("--course-code", String(course.code || ""))
    }
    visibilityProc.command = command
    visibilityProc.running = true
  }

  Process {
    id: statusProc
    command: [root.helperPath, "fetch", "--json", "--days", String(root.days)]
    environment: ({ "CANVAS_BASE_URL": root.baseUrl })
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    stderr: StdioCollector { id: statusError; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) {
        var message = String(statusError.text || "").trim()
        root.errorText = message !== "" ? message.replace(/^omacanvas:\s*/, "")
                                            : "Canvas could not be refreshed."
        return
      }
      try {
        root.payload = JSON.parse(String(statusOutput.text || ""))
        root.ensureSelectedCourse()
        root.errorText = ""
      } catch (error) {
        root.errorText = "Canvas returned data the bar could not read."
      }
      if (root.refreshAfterStatus) {
        root.refreshAfterStatus = false
        Qt.callLater(function() { root.refreshNow() })
      }
    }
  }

  Process {
    id: visibilityProc
    environment: ({ "CANVAS_BASE_URL": root.baseUrl })
    stderr: StdioCollector { id: visibilityErrorOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var message = String(visibilityErrorOutput.text || "").trim()
        root.visibilityError = message !== "" ? message.replace(/^omacanvas:\s*/, "")
                                                  : "Could not update the hidden course list."
      } else {
        if (root.pendingHiddenState) root.selectedCourseId = ""
        if (statusProc.running) root.refreshAfterStatus = true
        else root.refreshNow()
      }
      root.pendingVisibilityCourse = null
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: root.baseUrl !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNow()
  }

  onBaseUrlChanged: {
    if (baseUrl !== "" && errorText === configurationMessage) errorText = ""
    else if (baseUrl === "" && !loading) errorText = configurationMessage
  }

  Component.onCompleted: if (baseUrl === "") errorText = configurationMessage

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: "io.github.christopherhaynes33.omacanvas"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function nextPane(): string { root.selectPane(root.selectedPane + 1); return root.paneNames[root.selectedPane] }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0ae"
    active: root.errorText !== "" || root.urgentCount > 0
    tooltipText: root.errorText !== ""
      ? "Omacanvas — " + root.errorText
      : "Omacanvas — " + root.pendingCount + " assignment" + (root.pendingCount === 1 ? "" : "s")
        + " due · right-click to refresh"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.selectPane(root.selectedPane + dx)
        if (dy !== 0)
          panelFlick.contentY = Math.max(0, Math.min(
            panelFlick.contentY + dy * Style.space(56),
            Math.max(0, panelFlick.contentHeight - panelFlick.height)))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refreshNow()
        else if (text === "1") root.selectPane(0)
        else if (text === "2") root.selectPane(1)
        else if (text === "3") root.selectPane(2)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            title: "Omacanvas"
            meta: root.fetchedLabel()
            detail: root.loading ? "…" : root.pendingCount + " DUE"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "\uf0ae"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Row {
            id: paneSwitch
            width: parent.width
            spacing: Style.spacing.md
            readonly property real cellWidth: (width - spacing * (root.paneNames.length - 1)) / root.paneNames.length

            Repeater {
              model: root.paneNames
              Button {
                required property string modelData
                required property int index
                width: paneSwitch.cellWidth
                text: modelData
                selected: index === root.selectedPane
                hasCursor: root.cursorActive && index === root.selectedPane
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.selectPane(index)
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.errorText === "" && !root.loading
              && root.courses.length === 0 && root.hiddenCourses.length === 0
            width: parent.width
            text: "No active student courses were found."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.visibilityError !== ""
            width: parent.width
            text: root.visibilityError
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            id: overviewPane
            visible: root.errorText === "" && root.selectedPane === 0
            width: parent.width
            spacing: Style.space(12)

            Row {
              id: overviewSummary
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: [
                  { value: root.pendingCount, label: "DUE", alarming: false },
                  { value: root.urgentCount, label: "48 HOURS", alarming: root.urgentCount > 0 },
                  { value: root.courses.length, label: "COURSES", alarming: false }
                ]
                Row {
                  required property var modelData
                  required property int index
                  spacing: Style.space(4)

                  Text {
                    visible: index > 0
                    text: "·"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: modelData.value + " " + modelData.label
                    color: modelData.alarming ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "COURSE GRADES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.courses
              Column {
                required property var modelData
                required property int index
                width: overviewPane.width
                spacing: Style.space(7)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(overviewName.implicitHeight, overviewGrade.implicitHeight)
                  Text {
                    id: overviewName
                    anchors.left: parent.left
                    anchors.right: overviewGrade.left
                    anchors.rightMargin: Style.space(12)
                    text: modelData.name
                    textFormat: Text.PlainText
                    color: overviewCourseLink.containsMouse ? root.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight

                    MouseArea {
                      id: overviewCourseLink
                      anchors.fill: parent
                      enabled: root.canvasItemUrl(modelData) !== ""
                      hoverEnabled: enabled
                      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: root.openCourse(modelData)
                    }
                  }
                  Text {
                    id: overviewGrade
                    anchors.right: parent.right
                    text: root.grade(modelData)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }

                PanelSeparator {
                  visible: index < root.courses.length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            Text {
              visible: root.assignments.length > 0
              width: parent.width
              text: root.assignments.length > 0
                ? "Next: " + root.dueLabel(root.assignments[0].due_at) + " — " + root.assignments[0].name
                : ""
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            id: assignmentsPane
            visible: root.errorText === "" && root.selectedPane === 1
            width: parent.width
            spacing: Style.space(9)

            PanelSectionHeader {
              text: "NEXT " + root.days + " DAYS · " + root.pendingCount + " OPEN · " + root.submittedCount + " SUBMITTED"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.assignments.length === 0
              width: parent.width
              text: "No assignments are due in this window."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.assignments
              Column {
                required property var modelData
                required property int index
                width: assignmentsPane.width
                spacing: Style.space(4)

                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: String(modelData.course_code || modelData.course_name || "")
                    + " · " + root.dueLabel(modelData.due_at)
                  submitted: !!modelData.submitted
                  linkAvailable: root.canvasItemUrl(modelData) !== ""
                  foreground: root.foreground
                  muted: root.dim
                  accent: root.urgent
                  fontFamily: root.fontFamily
                  onActivated: root.openAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < root.assignments.length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }
          }

          Column {
            id: coursesPane
            visible: root.errorText === "" && root.selectedPane === 2
            width: parent.width
            spacing: Style.space(10)

            Item {
              visible: !!root.selectedCourse
              width: parent.width
              implicitHeight: Math.max(coursePosition.implicitHeight, hideCourseAction.implicitHeight)

              PanelSectionHeader {
                id: coursePosition
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "COURSE " + (root.selectedCourseIndex + 1) + " OF " + root.courses.length
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelActionButton {
                id: hideCourseAction
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf070"
                tooltipText: visibilityProc.running && root.pendingHiddenState
                  ? "Hiding course…" : "Hide course"
                enabled: !visibilityProc.running
                foreground: root.foreground
                hoverColor: root.urgent
                fontFamily: root.fontFamily
                onClicked: root.setCourseVisibility(root.selectedCourse, true)
              }
            }

            Item {
              visible: !!root.selectedCourse
              width: parent.width
              implicitHeight: Math.max(previousCourse.implicitHeight, courseCode.implicitHeight, nextCourse.implicitHeight)

              PanelActionButton {
                id: previousCourse
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf053"
                tooltipText: "Previous course"
                enabled: root.courses.length > 1
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.selectCourseOffset(-1)
              }

              Text {
                id: courseCode
                anchors.left: previousCourse.right
                anchors.right: nextCourse.left
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.selectedCourse
                  ? root.courseLabel(root.selectedCourse, root.selectedCourseIndex) : ""
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }

              PanelActionButton {
                id: nextCourse
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf054"
                tooltipText: "Next course"
                enabled: root.courses.length > 1
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.selectCourseOffset(1)
              }
            }

            Text {
              id: selectedCourseName
              visible: !!root.selectedCourse
              width: parent.width
              text: root.selectedCourse ? root.selectedCourse.name : ""
              textFormat: Text.PlainText
              color: selectedCourseLink.containsMouse ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap

              MouseArea {
                id: selectedCourseLink
                anchors.fill: parent
                enabled: root.canvasItemUrl(root.selectedCourse) !== ""
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.openCourse(root.selectedCourse)
              }
            }

            Text {
              visible: !!root.selectedCourse
              width: parent.width
              text: root.selectedCourse ? "Current grade  ·  " + root.grade(root.selectedCourse) : ""
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            PanelSectionHeader {
              visible: !!root.selectedCourse
              text: "UPCOMING ASSIGNMENTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.selectedCourse && (root.selectedCourse.assignments || []).length === 0
              width: parent.width
              text: "No assignments due in the next " + root.days + " days."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.selectedCourse ? (root.selectedCourse.assignments || []) : []
              Column {
                required property var modelData
                required property int index
                width: coursesPane.width
                spacing: Style.space(4)

                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: root.dueLabel(modelData.due_at)
                  submitted: !!modelData.submitted
                  linkAvailable: root.canvasItemUrl(modelData) !== ""
                  foreground: root.foreground
                  muted: root.dim
                  accent: root.urgent
                  fontFamily: root.fontFamily
                  onActivated: root.openAssignment(modelData)
                }
                PanelSeparator {
                  visible: root.selectedCourse
                    && index < (root.selectedCourse.assignments || []).length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            Button {
              visible: root.hiddenCourses.length > 0
              width: parent.width
              text: root.hiddenCourses.length + " hidden course"
                + (root.hiddenCourses.length === 1 ? "" : "s")
              iconText: root.hiddenCoursesExpanded ? "\uf078" : "\uf054"
              bordered: false
              leftAlign: true
              foreground: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              iconSize: Style.font.caption
              horizontalPadding: 0
              onClicked: root.hiddenCoursesExpanded = !root.hiddenCoursesExpanded
            }

            Text {
              visible: root.hiddenCoursesExpanded && root.hiddenCourses.length > 0
              width: parent.width
              text: "Hidden courses are excluded from grades, assignments, counts, alerts, and assignment API requests."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.hiddenCoursesExpanded ? root.hiddenCourses : []
              Column {
                required property var modelData
                required property int index
                width: coursesPane.width
                spacing: Style.space(7)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(hiddenCourseText.implicitHeight, unhideCourseAction.implicitHeight)

                  Column {
                    id: hiddenCourseText
                    anchors.left: parent.left
                    anchors.right: unhideCourseAction.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)
                    Text {
                      width: parent.width
                      text: modelData.name
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                    Text {
                      visible: String(modelData.code || "") !== ""
                      width: parent.width
                      text: String(modelData.code || "")
                      textFormat: Text.PlainText
                      color: Qt.darker(root.dim, 1.25)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  PanelActionButton {
                    id: unhideCourseAction
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "\uf06e"
                    tooltipText: visibilityProc.running && !root.pendingHiddenState
                      && root.pendingVisibilityCourse
                      && String(root.pendingVisibilityCourse.id) === String(modelData.id)
                      ? "Unhiding course…" : "Unhide course"
                    enabled: !visibilityProc.running
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    onClicked: root.setCourseVisibility(modelData, false)
                  }
                }

                PanelSeparator {
                  visible: index < root.hiddenCourses.length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.12
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground; opacity: 0.45 }

          Text {
            width: parent.width
            text: "Right-click the bar icon or press R to refresh · ←/→ changes views"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
