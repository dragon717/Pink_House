import SwiftUI
import SwiftData
import PhotosUI

extension View {

    func bookDetailSheets(
        showingTrash: Binding<Bool>,
        showingCoverPicker: Binding<Bool>,
        selectedCoverItem: Binding<PhotosPickerItem?>,
        updateCover: @escaping (PhotosPickerItem) -> Void,
        showingBackgroundPicker: Binding<Bool>,
        selectedBackgroundItem: Binding<PhotosPickerItem?>,
        tempBackgroundImage: Binding<UIImage?>,
        showingBackgroundCropper: Binding<Bool>,
        backgroundCropperSheet: @escaping () -> some View,
        showingRenameAlert: Binding<Bool>,
        newPageName: Binding<String>,
        pageToRename: Binding<Outfit?>,
        saveRename: @escaping () -> Void,
        showingMoveSheet: Binding<Bool>,
        movePageSheet: @escaping () -> some View
    ) -> some View {
        self
            .sheet(isPresented: showingTrash) {
                RecycleBinSheetView(initialTab: 1)
            }
            .photosPicker(isPresented: showingCoverPicker, selection: selectedCoverItem, matching: .images)
            .onChange(of: selectedCoverItem.wrappedValue) { _, newItem in
                if let newItem {
                    updateCover(newItem)
                }
            }
            .photosPicker(isPresented: showingBackgroundPicker, selection: selectedBackgroundItem, matching: .images)
            .onChange(of: selectedBackgroundItem.wrappedValue) { _, newItem in
                if let newItem {
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                tempBackgroundImage.wrappedValue = image
                                showingBackgroundCropper.wrappedValue = true
                                selectedBackgroundItem.wrappedValue = nil
                            }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: showingBackgroundCropper) {
                backgroundCropperSheet()
            }
            .alert("重命名".appLocalized, isPresented: showingRenameAlert) {
                TextField("名称".appLocalized, text: newPageName)
                Button("取消".appLocalized, role: .cancel) {}
                Button("确定".appLocalized) {
                    saveRename()
                }
            }
            .sheet(isPresented: showingMoveSheet) {
                movePageSheet()
            }
            .navigationDestination(for: Outfit.self) { outfit in
                PageFlipEditorContainer(initialOutfit: outfit)
            }
    }
}
