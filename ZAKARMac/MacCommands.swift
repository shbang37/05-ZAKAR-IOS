import SwiftUI

// ============================================================
// MacCommands — 메뉴바 명령 (HIG: 단축키 발견 가능성)
// 보기: 모드 전환 (⌘⌥1/2/3) · 편집: Undo/Redo 자리 (Phase 7에서 실제 연결)
// ============================================================

struct MacCommands: Commands {
    @ObservedObject var appState: MacAppState

    var body: some Commands {
        // 편집 메뉴 Undo/Redo(⌘Z)는 시스템 기본 항목이 윈도우 UndoManager와 자동 연결
        // (registerUndo/setActionName으로 "정리 취소" 등 액션명 표시)

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
