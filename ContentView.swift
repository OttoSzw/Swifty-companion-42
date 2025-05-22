//
//  ContentView.swift
//  42App
//
//  Created by Otto Szwalberg on 10/04/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View
{
    @State private var searchText = ""
    @State private var userExists: Bool? = nil
    @State private var userData: [String: Any]? = nil
    @State private var showDetail = false
    
    @State private var accessToken: String? = nil
    @State private var tokenExpirationDate: Date? = nil

    @State private var showNoNetworkAlert = false

    @StateObject private var networkMonitor = NetworkMonitor()

    let uid = "u-s4t2ud-3b3be069f26c9c2044d2eb15d2efb4c357758f5907c3cab7b1f691269b026069"
    var secret: String = ""
    
    init() {
            if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
               let xml = FileManager.default.contents(atPath: path),
               let config = try? PropertyListSerialization.propertyList(from: xml, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {

                if let apiKey = config["API_KEY"] as? String {
                    self.secret = apiKey
                    print("API Key: \(secret)")
                } else {
                    print("Clé API_KEY introuvable dans le .plist")
                }
            } else {
                print("Erreur de lecture du fichier Config.plist")
            }
        }

    var body: some View
    {
        NavigationStack
        {
            ZStack
            {
                Image("Back42")
                    .resizable()
                    .ignoresSafeArea()
                VStack(spacing: 20)
                {
                    Image("42logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)

                    HStack
                    {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Enter a login", text: $searchText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(15)
                    .background(Color.white)
                    .cornerRadius(50)
                    .padding(.horizontal)

                    Button("Check login") {
                        if networkMonitor.isConnected {
                            checkLogin(login: searchText)
                        } else {
                            showNoNetworkAlert = true
                        }
                    }
                    .alert("Pas de connexion Internet", isPresented: $showNoNetworkAlert){
                        Button("OK", role: .cancel) { }
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                    .cornerRadius(20)

                    if let exists = userExists {
                        Text(exists ? "" : "❌ Utilisateur introuvable")
                    }

                    NavigationLink(
                        destination: UserDetailView(userData: userData ?? [:])
                            .id(userData?["login"] as? String ?? UUID().uuidString),
                        isActive: $showDetail
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }
    
    func checkLogin(login: String)
    {
        if let token = accessToken,
           let expiry = tokenExpirationDate,
           expiry > Date()
        {
            fetchUser(login: login, token: token)
        }
        else
        {
            getAccessToken { token in
                guard let token = token else { return }
                DispatchQueue.main.async {
                    self.accessToken = token
                    self.tokenExpirationDate = Date().addingTimeInterval(7200) // 2h
                    fetchUser(login: login, token: token)
                }
            }
        }
    }
    
    func fetchUser(login: String, token: String)
    {
        let url = URL(string: "https://api.intra.42.fr/v2/users/\(login)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                DispatchQueue.main.async {
                    if httpResponse.statusCode == 200 {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            self.userExists = true
                            self.userData = json
                            self.showDetail = true
                            print("Réponse JSON: \(json)")
                        }
                    } else {
                        self.userExists = false
                    }
                }
            }
        }.resume()
    }
    
    func getAccessToken(completion: @escaping (String?) -> Void) {
        let url = URL(string: "https://api.intra.42.fr/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let bodyParams = [
            "grant_type": "client_credentials",
            "client_id": uid,
            "client_secret": secret
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                completion(nil)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String {
                completion(token)
            } else {
                completion(nil)
            }
        }.resume()
    }
}

struct UserDetailView: View {
    var userData: [String: Any]
    var currentXP: Float {
        extractLevel(from: userData)
    }
    let maxXP: Float = 100
    @State private var animatedXP: Float = 0
    var projects: [[String: Any]] {
        return userData["projects_users"] as? [[String: Any]] ?? []
    }
    @State private var displayedWallet = 0
    @State private var targetWallet = 0
    @State private var selectedTab: String = "projects"

    var body: some View {
        ZStack {
            Image("Back42")
                .resizable()
                .ignoresSafeArea()
            VStack(spacing: 20) {
                if let imageUrlString = (userData["image"] as? [String: Any])?["link"] as? String,
                   let imageUrl = URL(string: imageUrlString) {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image.resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 4))
                                .shadow(radius: 10)
                        case .failure:
                            Image(systemName: "photo")
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Text("Image non disponible")
                        .foregroundColor(.gray)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                }
                Text(userData["displayname"] as? String ?? "Nom inconnu")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(2)
                    .shadow(color: .black, radius: 3)

                VStack
                {
                    Group
                    {
                        HStack {
                            Text("Login :")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(5)
                            
                            Spacer()
                            Text(userData["login"] as? String ?? "Inconnu")
                                .foregroundColor(.white)
                                .font(.system(size: 18, weight: .bold))
                                .padding(5)
                        }
                        HStack {
                            Text("Location :")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(5)
                            Spacer()
                            Text(userData["location"] as? String ?? "Inconnue")
                                .foregroundColor(.white)
                                .font(.system(size: 18, weight: .bold))
                                .padding(5)
                        }
                        HStack {
                            HStack {
                                Text("Wallet :")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(5)
                                Spacer()
                                if targetWallet >= 0
                                {
                                    Text("+ \(displayedWallet) ₳")
                                        .foregroundColor(.green)
                                        .font(.system(size: 18, weight: .bold))
                                        .padding(5)
                                } 
                                else
                                {
                                    Text("Inconnu")
                                        .foregroundColor(.white)
                                        .font(.system(size: 18, weight: .bold))
                                        .padding(5)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding([.leading, .trailing], 5)
                
                VStack(alignment: .leading, spacing: 8)
                {
                    let fullLevel = Int(currentXP)
                    let xpProgress = currentXP - Float(fullLevel)
                    let formattedLevel = String(format: "%.2f", currentXP)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 20)
                            .frame(height: 20)
                            .foregroundColor(Color.white.opacity(0.7))

                        RoundedRectangle(cornerRadius: 20)
                            .frame(width: CGFloat(animatedXP) * UIScreen.main.bounds.width * 0.8, height: 20)
                            .foregroundColor(.cyan)

                        Text("Lv \(formattedLevel)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: /*@START_MENU_TOKEN@*/10/*@END_MENU_TOKEN@*/)
                            .frame(maxWidth: .infinity)
                            .padding(.leading, 8)
                    }
                    .onAppear
                    {
                        withAnimation(.easeInOut(duration: 1.0)) {
                            animatedXP = xpProgress
                            if let wallet = userData["wallet"] as? Int {
                                targetWallet = wallet
                                displayedWallet = 0

                                Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { timer in
                                    if displayedWallet < targetWallet {
                                        displayedWallet += 1
                                    } else {
                                        timer.invalidate()
                                    }
                                }
                            }

                        }
                    }
                }
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding([.leading, .trailing], 5)
                
                

                VStack(alignment: .leading, spacing: 12) {

                    HStack {
                        Button(action: { selectedTab = "projects" }) {
                            Text("Projects")
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .foregroundColor(selectedTab == "projects" ? Color.white : Color.white.opacity(0.3))
                                .cornerRadius(10)
                        }

                        Button(action: { selectedTab = "skills" }) {
                            Text("Skills")
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .foregroundColor(selectedTab == "skills" ? Color.white : Color.white.opacity(0.3))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)

                    if selectedTab == "projects" {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(Array(projects.enumerated()), id: \.offset)
                                { _, project in
                                    if let projectInfo = project["project"] as? [String: Any],
                                       let name = projectInfo["name"] as? String,
                                       let validated = project["validated?"] as? Bool,
                                       let mark = project["final_mark"] as? Int
                                    {

                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.white.opacity(0.2))
                                                HStack
                                                {
                                                    VStack(alignment: .leading)
                                                    {
                                                        Text(name)
                                                            .font(.headline)
                                                            .foregroundColor(.white)
                                                            .padding(5)
                                                        Text("Note: \(mark)")
                                                            .font(.subheadline)
                                                            .foregroundColor(validated ? .green : .red)
                                                            .padding(5)
                                                    }
                                                    Spacer()
                                                    Image(systemName: validated ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                                        .foregroundColor(validated ? .green : .red)
                                                        .imageScale(.large)
                                                }
                                                .padding()
                                                .frame(height: 50)
                                    }
                                }
                            }
                            .padding(.vertical)
                            .padding(.horizontal)
                        }
                        .frame(height: 280)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else if selectedTab == "skills" {
                        ScrollView {
                            VStack(spacing: 8) {
                                let skills = (userData["cursus_users"] as? [[String: Any]])?
                                    .first(where: { ($0["cursus_id"] as? Int) == 21 })?["skills"] as? [[String: Any]] ?? []

                                ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in
                                    if let name = skill["name"] as? String,
                                       let levelValue = skill["level"] as? Double {

                                        VStack(alignment: .leading) {
                                            Text(name)
                                                .font(.headline)
                                                .foregroundColor(.white)

                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color.white.opacity(0.2))
                                                    .frame(height: 12)

                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color.cyan)
                                                    .frame(width: CGFloat(levelValue) * 25, height: 12)
                                            }

                                            Text(String(format: "%.2f", levelValue))
                                                .font(.caption)
                                                .foregroundColor(.cyan)
                                        }
                                        .padding(.vertical, 5)
                                    }
                                }
                            }
                            .padding()
                        }
                        .frame(height: 280)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(.horizontal)
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding([.leading, .trailing], 5)
            }
            .padding(.top)
        }
        .navigationTitle("Détails de l'utilisateur")
    }
}


func extractLevel(from data: [String: Any]) -> Float {
    guard let cursusUsers = data["cursus_users"] as? [[String: Any]] else { return 0 }
    if let mainCursus = cursusUsers.first(where: { ($0["cursus_id"] as? Int) == 21 }),
       let level = mainCursus["level"] as? Double {
        return Float(level)
    }
    return 0
}

#Preview {
    //        let mockUser: [String: Any] = [
    //            "login": "oszwalbe",
    //            "displayname": "Otto Szwalberg",
    //            "wallet": 124,
    //            "location": "Cluster B1",
    //            "image": ["link": "https://cdn.intra.42.fr/users/oszwalbe.jpg"],
    //            "cursus_users": [["cursus_id": 21, "level": 4.7]],
    //            "projects_users": [
    //                [
    //                    "project": ["name": "Libft"],
    //                    "validated?": true,
    //                    "final_mark": 115
    //                ],
    //                [
    //                    "project": ["name": "get_next_line"],
    //                    "validated?": false,
    //                    "final_mark": 80
    //                ]
    //            ]
    //        ]
    //        return UserDetailView(userData: mockUser)
        ContentView()
}
