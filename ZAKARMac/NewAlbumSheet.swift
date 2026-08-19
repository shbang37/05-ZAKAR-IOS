import SwiftUI

// ============================================================
// NewAlbumSheet — ⌘N 새 앨범
// 리뷰 모드의 ⌘1~9 이동 대상(사용자 앨범)을 사진 앱을 열지 않고 바로 만든다.
// ============================================================

struct NewAlbumSheet: View {
    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isCreating = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("새 앨범")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            TextField("앨범 이름", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { create() }
                .frame(width: 280)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                Text("만든 앨범은 리뷰 모드에서 ⌘1~9로 바로 이동 대상이 됩니다.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.subText)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isCreating ? "만드는 중…" : "만들기") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 340)
        .background(AppTheme.midPurple)
        .onAppear { fieldFocused = true }
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                try await photoManager.createAlbum(named: name)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
