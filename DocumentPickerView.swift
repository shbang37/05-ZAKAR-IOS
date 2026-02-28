import SwiftUI
import UniformTypeIdentifiers

// MARK: - 문서 선택 뷰
struct DocumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var googleDrive: GoogleDriveService
    @EnvironmentObject private var auth: AuthService
    
    @State private var selectedURLs: [URL] = []
    @State private var eventName: String = ""
    @State private var showPicker = false
    @State private var showUploadConfirmation = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.mainPurple
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    if selectedURLs.isEmpty {
                        emptyStateView
                    } else {
                        selectedFilesView
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("문서 선택")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !selectedURLs.isEmpty {
                        Button {
                            showUploadConfirmation = true
                        } label: {
                            Text("다음")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.gracefulGold)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPicker) {
            DocumentPicker(selectedURLs: $selectedURLs)
        }
        .sheet(isPresented: $showUploadConfirmation) {
            uploadConfirmationView
        }
        .onAppear {
            showPicker = true
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.3))
            
            Text("문서를 선택하세요")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            
            Button {
                showPicker = true
            } label: {
                Text("문서 선택")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.gracefulGold)
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
    }
    
    private var selectedFilesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(selectedURLs.count)개 파일 선택됨")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(selectedURLs, id: \.self) { url in
                        fileRow(url: url)
                    }
                }
            }
            
            Button {
                showPicker = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("파일 추가")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.gracefulGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AppTheme.gracefulGold.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private func fileRow(url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForFile(url))
                .font(.system(size: 24))
                .foregroundColor(AppTheme.gracefulGold)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let size = fileSize(url: url) {
                    Text(size)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Spacer()
            
            Button {
                selectedURLs.removeAll { $0 == url }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(12)
        .background(AppTheme.darkPurple.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.gracefulGold.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private var uploadConfirmationView: some View {
        NavigationView {
            ZStack {
                AppTheme.mainPurple
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        eventNameInputCard
                        uploadPathPreview
                        uploadButton
                        
                        Spacer(minLength: 30)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("업로드 확인")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showUploadConfirmation = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var eventNameInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.9))
                Text("이벤트명")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text("업로드할 폴더의 이벤트명을 입력하세요")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            
            TextField("예: 주일예배, 수련회, 크리스마스", text: $eventName)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
        .padding(16)
        .background(GlassCard())
    }
    
    private var uploadPathPreview: some View {
        let department = auth.currentUser?.department ?? "부서"
        let year = Calendar.current.component(.year, from: Date())
        let dateStr = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        let folderPath = "ZAKAR/\(department)/\(year)/\(dateStr)_\(eventName.isEmpty ? "이벤트명" : eventName)/"
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.9))
                Text("업로드 경로 미리보기")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("폴더")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Text(folderPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(GlassCard())
    }
    
    private var uploadButton: some View {
        Button {
            Task {
                await startUpload()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(selectedURLs.count)개 파일 업로드 시작")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.gracefulGold)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: AppTheme.gracefulGold.opacity(0.3), radius: 10, y: 4)
        }
        .disabled(eventName.isEmpty)
        .opacity(eventName.isEmpty ? 0.5 : 1)
        .padding(16)
        .background(GlassCard())
    }
    
    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "play.rectangle.fill"
        case "txt": return "text.alignleft"
        default: return "doc.fill"
        }
    }
    
    private func fileSize(url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func startUpload() async {
        guard !selectedURLs.isEmpty else { return }
        
        showUploadConfirmation = false
        
        let department = auth.currentUser?.department ?? "미분류"
        
        // TODO: Google Drive 문서 업로드 구현
        // 현재는 PHAsset 기반 uploadAssets만 있으므로
        // URL 기반 업로드 메서드가 필요합니다
        
        print("[DocumentPicker] Upload \(selectedURLs.count) documents")
        print("[DocumentPicker] Department: '\(department)', eventName: '\(eventName)'")
        
        // 화면 닫기
        selectedURLs.removeAll()
        dismiss()
    }
}

// MARK: - UIDocumentPickerViewController Wrapper
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedURLs: [URL]
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [
                .pdf,
                .text,
                UTType(filenameExtension: "doc")!,
                UTType(filenameExtension: "docx")!,
                UTType(filenameExtension: "xls")!,
                UTType(filenameExtension: "xlsx")!,
                UTType(filenameExtension: "ppt")!,
                UTType(filenameExtension: "pptx")!
            ],
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.selectedURLs.append(contentsOf: urls)
        }
    }
}
