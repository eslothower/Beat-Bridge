import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var currentPage = 0
    
    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1
            OnboardingPageView(
                image: "square.and.arrow.up",
                title: "Welcome to Beat Bridge",
                description: "Share music between any streaming service with just a few taps.",
                pageNumber: 0,
                currentPage: $currentPage,
                totalPages: 3
            )
            .tag(0)
            
            // Page 2
            OnboardingPageView(
                image: "square.and.arrow.up.circle",
                title: "Enable in Share Sheet",
                description: "To use Beat Bridge, you'll need to enable it in your share sheet.\n\n1. Find a song in any music app\n2. Tap the share button\n3. Scroll right in the apps row and tap 'More'\n4. Enable Beat Bridge and drag it to the top for easy access",
                pageNumber: 1,
                currentPage: $currentPage,
                totalPages: 3
            )
            .tag(1)
            
            // Page 3
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                
                Text("Remember Friends' Preferences")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Beat Bridge will remember which music service each of your friends uses, so sharing becomes even faster next time.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                Button(action: {
                    // Complete onboarding
                    hasCompletedOnboarding = true
                }) {
                    Text("Get Started")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 50)
                
                HStack {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i == 2 ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top)
            }
            .padding()
            .tag(2)
        }
        .tabViewStyle(PageTabViewStyle())
        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
    }
}

struct OnboardingPageView: View {
    let image: String
    let title: String
    let description: String
    let pageNumber: Int
    @Binding var currentPage: Int
    let totalPages: Int
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: image)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(description)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    currentPage += 1
                }
            }) {
                Text("Next")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 50)
            
            HStack {
                ForEach(0..<totalPages) { i in
                    Circle()
                        .fill(i == pageNumber ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top)
        }
        .padding()
    }
}
