import SwiftUI
import AppKit

// ============================================================
// MacCommands — 메뉴바 명령 (HIG: 단축키 발견 가능성)
// 보기: 모드 전환 (⌘⌥1/2) · 편집: Undo/Redo 자리 (Phase 7에서 실제 연결)
// ============================================================

struct MacCommands: Commands {
    @ObservedObject var appState: MacAppState

    private static var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    var body: some Commands {
        // 편집 메뉴 Undo/Redo — 시스템 기본 항목은 윈도우 UndoManager(=first responder 의존)에
        // 묶여 있어 detail 뷰에서 무반응이다. 앱 소유 UndoManager로 직접 연결한다.
        CommandGroup(replacing: .undoRedo) {
            // 글자를 입력하는 중(새 앨범 이름 등)이면 글자 되돌리기로 넘긴다 —
            // 그러지 않으면 시트 뒤에서 사진 작업이 조용히 되돌려진다
            Button("실행 취소") {
                if Self.isEditingText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                else { appState.performUndo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            Button("다시 실행") {
                if Self.isEditingText { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                else { appState.performRedo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        // 파일 메뉴 — 새 앨범 (⌘1~9 이동 대상이 되는 사용자 앨범 생성)
        CommandGroup(replacing: .newItem) {
            Button("새 앨범…") { appState.showNewAlbum = true }
                .keyboardShortcut("n", modifiers: .command)
        }

        // 보기 메뉴 — 모드 전환
        CommandMenu("보기") {
            Button("모든 사진") {
                appState.endReview()            // 리뷰 중이면 격자로
                appState.selection = .allPhotos
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            Button("유사 그룹") { appState.selection = .similarGroups }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Divider()
            Button("휴지통") { appState.selection = .trash }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }
}
