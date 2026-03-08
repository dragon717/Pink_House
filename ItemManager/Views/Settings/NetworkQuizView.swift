//
//  NetworkQuizView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2026/3/9.
//

import SwiftUI

// MARK: - 联网功能答题解锁视图
struct NetworkQuizView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var quizManager = QuizManager.shared
    @StateObject private var networkManager = NetworkSettingsManager.shared
    
    @State private var currentQuestions: [QuizQuestion] = []
    @State private var currentQuestionIndex = 0
    @State private var selectedAnswer: Int? = nil
    @State private var correctCount = 0
    @State private var showResult = false
    @State private var showExplanation = false
    @State private var isAnswerCorrect: Bool? = nil
    @State private var animateResult = false
    
    // 需要答对的题目数量
    private let requiredCorrectAnswers = 3
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                if showResult {
                    resultView
                } else {
                    quizContentView
                }
            }
            .navigationTitle("解锁联网功能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !showResult {
                        Button("退出") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            // 初始化题目
            currentQuestions = quizManager.getRandomQuestions(count: 3)
        }
    }
    
    // MARK: - 答题内容视图
    private var quizContentView: some View {
        VStack(spacing: 20) {
            // 进度指示器
            progressIndicator
                .padding(.top, 20)
            
            if currentQuestionIndex < currentQuestions.count {
                let question = currentQuestions[currentQuestionIndex]
                
                // 题目卡片
                questionCard(question: question)
                    .padding(.horizontal)
                
                // 选项列表
                optionsList(question: question)
                    .padding(.horizontal)
                
                Spacer()
                
                // 答案解析（答对后显示）
                if showExplanation, let isCorrect = isAnswerCorrect {
                    explanationView(question: question, isCorrect: isCorrect)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - 进度指示器
    private var progressIndicator: some View {
        VStack(spacing: 12) {
            // 进度条
            HStack(spacing: 8) {
                ForEach(0..<currentQuestions.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor(for: index))
                        .frame(height: 8)
                }
            }
            .padding(.horizontal)
            
            // 进度文字
            HStack {
                Text("题目 \(currentQuestionIndex + 1)/\(currentQuestions.count)")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.secondaryTextColor)
                
                Spacer()
                
                Text("已答对: \(correctCount)/\(requiredCorrectAnswers)")
                    .font(.subheadline)
                    .foregroundStyle(correctCount >= requiredCorrectAnswers ? .green : themeManager.secondaryTextColor)
            }
            .padding(.horizontal)
        }
    }
    
    private func progressColor(for index: Int) -> Color {
        if index < currentQuestionIndex {
            // 已完成的题目
            return .green
        } else if index == currentQuestionIndex {
            // 当前题目
            return themeManager.accentTextColor
        } else {
            // 未开始的题目
            return themeManager.secondaryTextColor.opacity(0.3)
        }
    }
    
    // MARK: - 题目卡片
    private func questionCard(question: QuizQuestion) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundStyle(themeManager.accentTextColor)
            
            Text(question.question)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(themeManager.primaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - 选项列表
    private func optionsList(question: QuizQuestion) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                OptionButton(
                    text: option,
                    isSelected: selectedAnswer == index,
                    isCorrect: isAnswerCorrect,
                    correctIndex: question.correctAnswer,
                    currentIndex: index,
                    themeManager: themeManager,
                    colorScheme: colorScheme
                ) {
                    if !showExplanation {
                        selectAnswer(index: index, question: question)
                    }
                }
                .disabled(showExplanation)
            }
        }
    }
    
    // MARK: - 答案解析视图
    private func explanationView(question: QuizQuestion, isCorrect: Bool) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isCorrect ? .green : .red)
                
                Text(isCorrect ? "回答正确！" : "回答错误")
                    .font(.headline)
                    .foregroundStyle(isCorrect ? .green : .red)
                
                Spacer()
            }
            
            Text(question.explanation)
                .font(.subheadline)
                .foregroundStyle(themeManager.secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button {
                nextQuestion()
            } label: {
                HStack {
                    Spacer()
                    Text(currentQuestionIndex < currentQuestions.count - 1 ? "下一题" : "查看结果")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding()
                .background(themeManager.accentTextColor)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCorrect ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - 结果视图
    private var resultView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 结果图标
            ZStack {
                Circle()
                    .fill(resultBackgroundColor)
                    .frame(width: 120, height: 120)
                
                Image(systemName: resultIconName)
                    .font(.system(size: 50))
                    .foregroundStyle(resultIconColor)
            }
            .scaleEffect(animateResult ? 1.0 : 0.5)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: animateResult)
            
            // 结果标题
            Text(resultTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(themeManager.primaryTextColor)
            
            // 结果描述
            Text(resultDescription)
                .font(.subheadline)
                .foregroundStyle(themeManager.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // 得分详情
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(correctCount)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("答对")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
                
                Divider()
                    .frame(height: 40)
                
                VStack(spacing: 4) {
                    Text("\(currentQuestions.count - correctCount)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                    Text("答错")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.15))
            )
            
            Spacer()
            
            // 操作按钮
            VStack(spacing: 12) {
                if isPassed {
                    Button {
                        unlockNetworkFeature()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "lock.open.fill")
                            Text("开启联网功能")
                                .font(.headline)
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding()
                        .background(themeManager.accentTextColor)
                        .cornerRadius(12)
                    }
                } else {
                    Button {
                        restartQuiz()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                            Text("重新挑战")
                                .font(.headline)
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding()
                        .background(themeManager.accentTextColor)
                        .cornerRadius(12)
                    }
                }
                
                Button {
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("稍后再说")
                            .font(.subheadline)
                            .foregroundStyle(themeManager.secondaryTextColor)
                        Spacer()
                    }
                    .padding()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                animateResult = true
            }
        }
    }
    
    // MARK: - 计算属性
    private var isPassed: Bool {
        correctCount >= requiredCorrectAnswers
    }
    
    private var resultIconName: String {
        isPassed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    private var resultIconColor: Color {
        isPassed ? .green : .red
    }
    
    private var resultBackgroundColor: Color {
        isPassed ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
    }
    
    private var resultTitle: String {
        isPassed ? "挑战成功！" : "挑战失败"
    }
    
    private var resultDescription: String {
        if isPassed {
            return "恭喜你答对了 \(correctCount) 道题！\n联网功能已解锁，你可以开始使用社区功能了。"
        } else {
            return "需要答对至少 \(requiredCorrectAnswers) 道题才能解锁联网功能。\n再试一次吧！"
        }
    }
    
    // MARK: - 方法
    private func selectAnswer(index: Int, question: QuizQuestion) {
        selectedAnswer = index
        isAnswerCorrect = (index == question.correctAnswer)
        
        if index == question.correctAnswer {
            correctCount += 1
        }
        
        showExplanation = true
    }
    
    private func nextQuestion() {
        if currentQuestionIndex < currentQuestions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswer = nil
            showExplanation = false
            isAnswerCorrect = nil
        } else {
            showResult = true
        }
    }
    
    private func restartQuiz() {
        currentQuestions = quizManager.getRandomQuestions(count: 3)
        currentQuestionIndex = 0
        correctCount = 0
        selectedAnswer = nil
        showExplanation = false
        isAnswerCorrect = nil
        showResult = false
        animateResult = false
    }
    
    private func unlockNetworkFeature() {
        networkManager.markQuizAsUnlocked()
        dismiss()
    }
}

// MARK: - 选项按钮
struct OptionButton: View {
    let text: String
    let isSelected: Bool
    let isCorrect: Bool?
    let correctIndex: Int
    let currentIndex: Int
    let themeManager: ThemeManager
    let colorScheme: ColorScheme
    let action: () -> Void
    
    private var backgroundColor: Color {
        if let correct = isCorrect {
            // 已选择并显示结果
            if currentIndex == correctIndex {
                return Color.green.opacity(colorScheme == .dark ? 0.3 : 0.2)
            } else if isSelected {
                return Color.red.opacity(colorScheme == .dark ? 0.3 : 0.2)
            } else {
                return themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.15)
            }
        } else if isSelected {
            // 已选择但未显示结果
            return themeManager.accentTextColor.opacity(colorScheme == .dark ? 0.3 : 0.2)
        } else {
            // 未选择
            return themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.15)
        }
    }
    
    private var borderColor: Color {
        if let correct = isCorrect {
            if currentIndex == correctIndex {
                return .green
            } else if isSelected {
                return .red
            } else {
                return Color.clear
            }
        } else if isSelected {
            return themeManager.accentTextColor
        } else {
            return Color.clear
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.body)
                    .foregroundStyle(themeManager.primaryTextColor)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                // 状态图标
                if let correct = isCorrect {
                    if currentIndex == correctIndex {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(themeManager.accentTextColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isSelected || (isCorrect != nil && currentIndex == correctIndex) ? 2 : 0)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 预览
#Preview {
    NetworkQuizView()
        .environment(ThemeManager.shared)
}
