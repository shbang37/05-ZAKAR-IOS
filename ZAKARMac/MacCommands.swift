import SwiftUI

// ============================================================
// MacCommands — 메뉴바 명령 (HIG: 단축키 발견 가능성)
// 보기: 모드 전환 (⌘⌥1/2/3) · 편집: Undo/Redo 자리 (Phase 7에서 실제 연결)
// ============================================================

struct MacCommands: Commands {
    @ObservedObject var appState: MacAppState

    var body: some Commands {
        // 편집 메뉴 Undo/Redo — 시스템 기본 항목은 윈도우 UndoManager(=first responder 의존)에
        // 묶여 있어 detail 뷰에서 무반응이다. 앱 소유 UndoManager로 직접 연결한다.
        CommandGroup(replacing: .undoRedo) {
            Button("실행 취소") { appState.undo.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("다시 실행") { appState.undo.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        // 파일 메뉴 — 새 앨범 (⌘1~9 이동 대상이 되는 사용자 앨범 생성)
        CommandGroup(replacing: .newItem) {
            Button("새 앨범…") { appState.showNewAlbum = true }
                .keyboardShortcut("n", modifiers: .command)
        }

        // 보기 메뉴 — 모드 전환
        CommandMenu("보기") {
            Button("모든 사진") { appState.selection = .allPhotos }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("유사 그룹") { appState.selection = .similarGroups }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("리뷰") { appState.selection = .review }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Divider()
            Button("휴지통") { appState.selection = .trash }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }
}
