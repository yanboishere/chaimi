import SwiftUI
import SwiftData

// MARK: - 设置

struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage("dailyCalorieLimit") private var dailyLimit: Double = 0
    @AppStorage("bodyProfile") private var profileJSON: String = ""
    @AppStorage("claudeModel") private var model: String = "claude-opus-5-5"

    @State private var profile = BodyProfile()
    @State private var keyInput = ""
    @State private var keySaved = KeychainStore.hasKey
    @State private var testResult: String? = nil
    @State private var testing = false
    @State private var confirmClearPantry = false
    @State private var confirmClearCalories = false

    private var tdee: Double { NutritionCalc.tdee(profile) }
    private var suggested: Double { NutritionCalc.suggestedCalories(profile) }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                Form {
                    goalSection
                    bodySection
                    aiSection
                    dataSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .onAppear { profile = BodyProfile.load(from: profileJSON) }
            .onChange(of: profile) { _, newValue in profileJSON = newValue.json }
        }
    }

    // MARK: 卡路里目标

    private var goalSection: some View {
        Section {
            HStack {
                Text("每日上限").font(.hand(16))
                Spacer()
                TextField("如 1800", value: $dailyLimit, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("千卡").font(.hand(14)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("按身体参数估算:基础代谢 \(Int(NutritionCalc.bmr(profile))) 千卡,日常消耗约 \(Int(tdee)) 千卡")
                    .font(.hand(13)).foregroundStyle(.secondary)
                Button {
                    dailyLimit = suggested
                } label: {
                    Text("按目标「\(profile.goal.label)」设为 \(Int(suggested)) 千卡")
                        .font(.hand(15))
                }
            }
        } header: { Text("卡路里目标").font(.hand(13)) }
        footer: { Text("估算用 Mifflin-St Jeor 公式,减脂目标下限 1200 千卡;只是参考,不是医疗建议。").font(.hand(11)) }
    }

    // MARK: 身体参数

    private var bodySection: some View {
        Section {
            Picker(selection: $profile.sex) {
                ForEach(BodyProfile.Sex.allCases, id: \.self) { Text($0.label).tag($0) }
            } label: { Text("性别").font(.hand(16)) }
            Stepper(value: $profile.age, in: 10...100) {
                HStack { Text("年龄").font(.hand(16)); Spacer(); Text("\(profile.age) 岁").font(.hand(15)) }
            }
            Stepper(value: $profile.heightCm, in: 120...220, step: 1) {
                HStack { Text("身高").font(.hand(16)); Spacer(); Text("\(Int(profile.heightCm)) cm").font(.hand(15)) }
            }
            Stepper(value: $profile.weightKg, in: 30...200, step: 0.5) {
                HStack { Text("体重").font(.hand(16)); Spacer(); Text(String(format: "%.1f kg", profile.weightKg)).font(.hand(15)) }
            }
            Picker(selection: $profile.activity) {
                ForEach(BodyProfile.Activity.allCases, id: \.self) { Text($0.label).tag($0) }
            } label: { Text("活动水平").font(.hand(16)) }
            Picker(selection: $profile.goal) {
                ForEach(BodyProfile.Goal.allCases, id: \.self) { Text($0.label).tag($0) }
            } label: { Text("目标").font(.hand(16)) }
        } header: { Text("身体参数(存在本机)").font(.hand(13)) }
    }

    // MARK: AI

    private var aiSection: some View {
        Section {
            if keySaved {
                HStack {
                    Label("已保存 API Key", systemImage: "checkmark.seal.fill")
                        .font(.hand(15)).foregroundStyle(Color.leafGreen)
                    Spacer()
                    Button("删除", role: .destructive) {
                        KeychainStore.deleteAPIKey()
                        keySaved = false; testResult = nil
                    }
                    .font(.hand(14))
                }
            } else {
                SecureField("粘贴 sk-ant- 开头的 API Key", text: $keyInput)
                    .font(.system(size: 14, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    if KeychainStore.saveAPIKey(keyInput) { keySaved = true; keyInput = "" }
                } label: { Text("保存到钥匙串").font(.hand(15)) }
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).count < 20)
            }

            Picker(selection: $model) {
                Text("Opus 5.5(默认,最聪明)").tag("claude-opus-5-5")
                Text("Sonnet 5.5(便宜一半)").tag("claude-sonnet-5-5")
                Text("Haiku 4.5(最省钱)").tag("claude-haiku-4-5")
            } label: { Text("模型").font(.hand(16)) }

            if keySaved {
                Button {
                    Task {
                        testing = true; defer { testing = false }
                        do { let m = try await ClaudeAPI.shared.testConnection(); testResult = "✅ 连接正常(\(m))" }
                        catch { testResult = "❌ \(error.localizedDescription)" }
                    }
                } label: {
                    if testing { ProgressView() } else { Text("测试连接").font(.hand(15)) }
                }
                if let testResult {
                    Text(testResult).font(.hand(13)).foregroundStyle(.secondary)
                }
            }
        } header: { Text("Anthropic API(可选)").font(.hand(13)) }
        footer: {
            Text("用于小票 AI 识别、联网搜菜谱和营养点评。Key 只存在本机钥匙串;识别时照片会发送到 Anthropic API,不经过任何第三方服务器。在 platform.claude.com 可以申请 Key。")
                .font(.hand(11))
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        Section {
            Button { SampleData.seed(into: context) } label: { Text("载入示例数据").font(.hand(15)) }
            Button(role: .destructive) { confirmClearPantry = true } label: { Text("清空库存").font(.hand(15)) }
                .confirmationDialog("确定清空所有库存食材?", isPresented: $confirmClearPantry, titleVisibility: .visible) {
                    Button("清空", role: .destructive) { SampleData.clearPantry(context) }
                }
            Button(role: .destructive) { confirmClearCalories = true } label: { Text("清空饮食记录").font(.hand(15)) }
                .confirmationDialog("确定清空所有卡路里记录?", isPresented: $confirmClearCalories, titleVisibility: .visible) {
                    Button("清空", role: .destructive) { SampleData.clearCalories(context) }
                }
        } header: { Text("数据").font(.hand(13)) }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section {
            LabeledContent { Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-").font(.hand(14)) } label: { Text("版本").font(.hand(15)) }
            Text("膳食建议量来自《中国居民平衡膳食宝塔(2022)》(中国营养学会)。")
                .font(.hand(13)).foregroundStyle(.secondary)
            Text("手绘图标由 rough.js 程序化生成;中文手写字体「站酷快乐体」,SIL OFL 1.1 许可。")
                .font(.hand(13)).foregroundStyle(.secondary)
        } header: { Text("关于柴米").font(.hand(13)) }
    }
}
