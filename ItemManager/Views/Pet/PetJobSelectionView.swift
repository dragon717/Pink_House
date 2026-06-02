import SwiftUI

struct PetJobSelectionView: View {
    @ObservedObject var viewModel: PetViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            List(PetJob.allCases) { job in
                Button {
                    if job == .none {
                        viewModel.stopJob()
                    } else {
                        viewModel.startJob(job)
                    }
                    isPresented = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: job.icon)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(job == viewModel.status.currentJob ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                            .clipShape(Circle())
                            .foregroundStyle(job == viewModel.status.currentJob ? .blue : .primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.localizedTitle)
                                .font(.headline)
                                .foregroundStyle(job == viewModel.status.currentJob ? .blue : .primary)
                            
                            Text(job.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                            
                            HStack(spacing: 12) {
                                if job.incomeRate > 0 {
                                    Label("%d/分".appLocalized(job.incomeRate), systemImage: "fish.circle.fill")
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("无收益".appLocalized)
                                        .foregroundStyle(.secondary)
                                }
                                
                                if job.consumptionMultiplier > 1.0 {
                                    Label("消耗 x%@".appLocalized(String(format: "%.1f", job.consumptionMultiplier)), systemImage: "bolt.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(.caption2)
                        }
                        
                        Spacer()
                        
                        if job == viewModel.status.currentJob {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .foregroundStyle(.primary) // 确保 Button 文字颜色正确
            }
            .navigationTitle("选择打工".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".appLocalized) {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
