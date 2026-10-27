// click x y [double]: a real mouse click at a screen point (for screenshots of the widget)
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
func post(_ t: CGEventType, _ n: Int64 = 1) {
    let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventClickState, value: n); e.post(tap: .cghidEventTap)
}
post(.mouseMoved); usleep(80000); post(.leftMouseDown); usleep(60000); post(.leftMouseUp)
if a.count > 3 { usleep(90000); post(.leftMouseDown, 2); usleep(60000); post(.leftMouseUp, 2) }
