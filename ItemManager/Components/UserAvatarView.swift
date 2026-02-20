import SwiftUI
import Foundation

struct UserAvatarView: View {
    let givenName: String
    let familyName: String
    let customAvatarPath: String?
    let size: CGFloat
    
    init(givenName: String, familyName: String, customAvatarPath: String? = nil, size: CGFloat) {
        self.givenName = givenName
        self.familyName = familyName
        self.customAvatarPath = customAvatarPath
        self.size = size
    }
    
    var initials: String {
        var components = PersonNameComponents()
        components.givenName = givenName
        components.familyName = familyName
        
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .abbreviated
        return formatter.string(from: components)
    }
    
    var body: some View {
        if let avatarPath = customAvatarPath,
           !avatarPath.isEmpty,
           let image = UIImage(contentsOfFile: avatarPath) {
            // 显示自定义头像
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if givenName.isEmpty && familyName.isEmpty {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.gray)
        } else {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: size, height: size)
        }
    }
}

#Preview {
    VStack {
        UserAvatarView(givenName: "John", familyName: "Appleseed", size: 60)
        UserAvatarView(givenName: "三", familyName: "张", size: 60)
        UserAvatarView(givenName: "", familyName: "", size: 60)
    }
}
