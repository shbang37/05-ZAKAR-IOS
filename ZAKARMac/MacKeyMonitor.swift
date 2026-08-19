import SwiftUI
import AppKit

// ============================================================
// MacKeyMonitor — keyCode 기반 키 처리 (NSEvent 로컬 모니터)
//
// SwiftUI `.onKeyPress`를 쓰지 않는 이유 두 가지:
//  1) **입력기 의존** — `.onKeyPress(KeyEquivalent("f"))`는 "입력된 문자"로 매칭한다.
//     한글 입력 상태에서 F는 'ㄹ'로 들어오므로 절대 매칭되지 않는다 (S도 동일).
//  2) **포커스 의존** — NavigationSplitView의 detail 뷰가 first responder를 잡지 못하면
//     (사이드바 List가 포커스를 쥔 채 진입하는 경우) 이벤트 자체가 오지 않는다.
//
// keyCode는 입력기·포커스와 무관한 물리 키 번호라 두 문제를 동시에 회피한다.
// 로컬 모니터는 key equivalent(⌘n) 디스패치보다 먼저 호출되므로,
// 리뷰 모드의 ⌘1~9(사진을 앨범으로 이동)가 루트의 ⌘1~9(앨범 화면 이동)보다 우선한다.
// ============================================================

enum MacKey: Equatable {
    case delete            // ⌫ Backspace / ⌦ Forward Delete
    case leftArrow, rightArrow, upArrow, downArrow
    case space, escape, enter
    case letterF, letterS, letterZ
    case digit(Int)        // 1~9

    init?(keyCode: UInt16) {
        switch keyCode {
        case 51, 117: self = .delete
        case 123: self = .leftArrow
        case 124: self = .rightArrow
        case 126: self = .upArrow
        case 125: self = .downArrow
        case 49:  self = .space
        case 53:  self = .escape
        case 36, 76: self = .enter
        case 3:   self = .letterF
        case 1:   self = .letterS
        case 6:   self = .letterZ
        case 18: self = .digit(1)
        case 19: self = .digit(2)
        case 20: self = .digit(3)
        case 21: self = .digit(4)
        case 23: self = .digit(5)
        case 22: self = .digit(6)
        case 26: self = .digit(7)
        case 28: self = .digit(8)
        case 25: self = .digit(9)
        default: return nil
        }
    }
}

/// 모니터 등록 상태와 최신 핸들러를 담는 참조 상자.
/// 클로저를 모니터에 그대로 넘기면 등록 시점의 뷰 상태(showQuickLook 등)를
/// 캡처한 채 굳어버리므로, 매 렌더마다 여기 갱신된 핸들러를 통해 호출한다.
@MainActor
final class MacKeyBox {
    var handler: (MacKey, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var monitor: Any?
}

struct MacKeyHandler: ViewModifier {
    let handler: (MacKey, NSEvent.ModifierFlags) -> Bool
    @State private var box = MacKeyBox()

    func body(content: Content) -> some View {
        box.handler = handler
        let box = box
        return content
            .onAppear {
                guard box.monitor == nil else { return }
                box.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    MainActor.assumeIsolated {
                        // 텍스트 편집 중에는 가로채지 않는다
                        if event.window?.firstResponder is NSTextView { return event }
                        guard let key = MacKey(keyCode: event.keyCode) else { return event }
                        return box.handler(key, event.modifierFlags) ? nil : event
                    }
                }
            }
            .onDisappear {
                if let m = box.monitor {
                    NSEvent.removeMonitor(m)
                    box.monitor = nil
                }
            }
    }
}

extension View {
    /// 이 뷰가 화면에 있는 동안 keyCode 기반으로 키를 처리한다.
    /// 핸들러가 `true`를 반환하면 이벤트를 소비(다른 곳으로 전달 안 함)한다.
    func macKeys(_ handler: @escaping (MacKey, NSEvent.ModifierFlags) -> Bool) -> some View {
        modifier(MacKeyHandler(handler: handler))
    }
}

extension NSEvent.ModifierFlags {
    /// ⌘/⌥/⌃ 없이 눌린 순수 키인지 (⇧·CapsLock·numericPad는 무시)
    var zakarIsPlainKey: Bool {
        !contains(.command) && !contains(.option) && !contains(.control)
    }
}
