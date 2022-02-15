/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The single entry point for the Scene Depth Point Cloud app.
*/

import SwiftUI
@main
struct PointCloudDepthSample: App {

    
    @State var loginSuccess: Bool = false
    @State var accout: String = ""
    //@State var userData: UserData = UserData()
    var body: some Scene {
        WindowGroup {
            if loginSuccess{
                MetalDepthView(account: accout)
            }else{
                LoginView(loginSuccess: $loginSuccess,account: $accout)
            }
        }
    }
}
