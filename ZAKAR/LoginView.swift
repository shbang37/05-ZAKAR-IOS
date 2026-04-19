import SwiftUI

// MARK: - 로그인 / 회원가입 화면
struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var confirmPassword = ""
    @State private var selectedDepartment = ""
    @State private var departments: [String] = []
    @State private var appear = false
    @FocusState private var focusField: Field?

    enum Mode { case signIn, signUp }
    enum Field { case name, email, password, confirmPassword }

    var body: some View {
        print("🔵 ZAKAR Log: LoginView.body - Rendering LoginView")
        return ZStack {
            // Premium background
            PremiumBackground(style: .warm)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // 로고
                    logoSection

                    Spacer().frame(height: 40)

                    // 탭 전환
                    modePicker
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 28)

                    // 입력 폼
                    formSection
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 20)

                    // 에러 메시지
                    if let error = auth.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red.opacity(0.85))
                                .font(.system(size: 14))
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.red.opacity(0.85))
                        }
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer().frame(height: 20)

                    // 액션 버튼
                    actionButton
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 40)

                    // 안내 문구
                    footerNote
                        .padding(.horizontal, 32)

                    Spacer().frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            print("🔵 ZAKAR Log: LoginView.onAppear - LoginView appeared")
            withAnimation(.easeOut(duration: 0.6)) { appear = true }
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
    }

    // MARK: - 로고
    private var logoSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            }
            .scaleEffect(appear ? 1 : 0.7)
            .opacity(appear ? 1 : 0)

            Text("ZAKAR")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .tracking(4)
                .opacity(appear ? 1 : 0)

            Text("교회 공동체의 소중한 순간을 함께 기록합니다")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .opacity(appear ? 1 : 0)
        }
    }

    // MARK: - 모드 피커
    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach([Mode.signIn, Mode.signUp], id: \.self) { m in
                Button {
                    withAnimation { mode = m; auth.errorMessage = nil }
                } label: {
                    Text(m == .signIn ? "로그인" : "동역자 등록")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(mode == m ? .white : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mode == m ? Color.white.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    // MARK: - 입력 폼
    private var formSection: some View {
        VStack(spacing: 12) {
            if mode == .signUp {
                inputField(
                    icon: "person.fill",
                    placeholder: "이름 (실명)",
                    text: $name,
                    field: .name
                )
                .transition(.move(edge: .top).combined(with: .opacity))

                // 부서 선택 드롭다운
                departmentPicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            inputField(
                icon: "envelope.fill",
                placeholder: "이메일",
                text: $email,
                field: .email,
                keyboardType: .emailAddress
            )

            inputField(
                icon: "lock.fill",
                placeholder: "비밀번호 (6자 이상)",
                text: $password,
                field: .password,
                isSecure: true
            )

            if mode == .signUp {
                inputField(
                    icon: "lock.fill",
                    placeholder: "비밀번호 확인",
                    text: $confirmPassword,
                    field: .confirmPassword,
                    isSecure: true
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: mode) {
            if mode == .signUp && departments.isEmpty {
                departments = await auth.fetchDepartments()
                // Firestore에 부서가 없으면 기본값 사용
                if departments.isEmpty {
                    departments = ["송도청", "또래청", "미들청", "열린청", "송도엘피스", "중고등부"]
                }
                if selectedDepartment.isEmpty { selectedDepartment = departments[0] }
            }
        }
    }

    // MARK: - 부서 피커
    private var departmentPicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 20)

            Menu {
                ForEach(departments, id: \.self) { dept in
                    Button(dept) { selectedDepartment = dept }
                }
            } label: {
                HStack {
                    Text(selectedDepartment.isEmpty ? "부서 선택" : selectedDepartment)
                        .font(.system(size: 15))
                        .foregroundColor(selectedDepartment.isEmpty ? .white.opacity(0.35) : .white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
        )
    }

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        keyboardType: UIKeyboardType = .default,
        isSecure: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 20)

            if isSecure {
                SecureField(placeholder, text: text)
                    .focused($focusField, equals: field)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .tint(.white)
                    .submitLabel(field == .confirmPassword || (mode == .signIn && field == .password) ? .done : .next)
                    .onSubmit { advanceFocus(from: field) }
            } else {
                TextField(placeholder, text: text)
                    .focused($focusField, equals: field)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .tint(.white)
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { advanceFocus(from: field) }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(focusField == field ? Color.white.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 0.8)
        )
    }

    private func advanceFocus(from field: Field) {
        switch field {
        case .name:            focusField = .email
        case .email:           focusField = .password
        case .password:        focusField = mode == .signUp ? .confirmPassword : nil
        case .confirmPassword: focusField = nil
        }
    }

    // MARK: - 액션 버튼
    private var actionButton: some View {
        Button {
            focusField = nil
            Task { await performAction() }
        } label: {
            ZStack {
                if auth.isLoading {
                    ProgressView().tint(.black).scaleEffect(0.9)
                } else {
                    Text(mode == .signIn ? "로그인" : "승인 요청하기")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isFormValid ? Color.white : Color.white.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!isFormValid || auth.isLoading)
    }

    // MARK: - 하단 안내
    private var footerNote: some View {
        Group {
            if mode == .signUp {
                Text("등록 후 관리자 승인이 완료되면\n앱을 사용할 수 있습니다.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            } else {
                Text("ZAKAR는 은혜의 교회 동역자 전용 앱입니다.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    // MARK: - 유효성
    private var isFormValid: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        let pwOK    = password.count >= 6
        if mode == .signIn { return emailOK && pwOK }
        return emailOK && pwOK && password == confirmPassword
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !selectedDepartment.isEmpty
    }

    private func performAction() async {
        if mode == .signIn {
            await auth.signIn(email: email.lowercased().trimmingCharacters(in: .whitespaces),
                              password: password)
        } else {
            guard password == confirmPassword else {
                auth.errorMessage = "비밀번호가 일치하지 않습니다."
                return
            }
            await auth.signUp(
                email: email.lowercased().trimmingCharacters(in: .whitespaces),
                password: password,
                name: name.trimmingCharacters(in: .whitespaces),
                department: selectedDepartment
            )
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService())
}
