import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item { // Model indicator
    id: root
    property string icon: "api"
    property string text: ""
    property string tooltipText: ""
    property real maximumTextWidth: -1
    property var clickAction: null
    property real padding: 4
    clip: true
    implicitHeight: rowLayout.implicitHeight + padding * 2
    implicitWidth: (iconItem.implicitWidth ?? iconItem.width) + rowLayout.spacing + (maximumTextWidth > 0 ? Math.min(providerName.implicitWidth, maximumTextWidth) : providerName.implicitWidth) + padding * 2

    RowLayout {
        id: rowLayout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.padding
            rightMargin: root.padding
        }

        MaterialSymbol {
            id: iconItem
            text: root.icon
            iconSize: Appearance.font.pixelSize.normal
        }
        StyledText {
            id: providerName
            Layout.fillWidth: true
            Layout.maximumWidth: root.maximumTextWidth > 0 ? root.maximumTextWidth : implicitWidth
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3onSurface
            elide: Text.ElideRight
            text: root.text
            animateChange: true
        }
    }

    Loader {
        active: root.tooltipText?.length > 0 || root.clickAction !== null
        anchors.fill: parent
        sourceComponent: MouseArea {
            id: mouseArea
            hoverEnabled: true
            cursorShape: root.clickAction !== null ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (root.clickAction !== null) root.clickAction();
            }

            StyledToolTip {
                id: toolTip
                extraVisibleCondition: false
                alternativeVisibleCondition: mouseArea.containsMouse // Show tooltip when hovered
                text: root.tooltipText
            }
        }
    }
}
