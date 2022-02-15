//
//  LoginView.swift
//  pointCloudSample
//
//  Created by apple on 2022/1/31.
//  Copyright © 2022 Apple. All rights reserved.
//


import SwiftUI

struct LoginView: View {
    @Binding var loginSuccess: Bool
    @Binding var account : String
    
    @State var pwd : String = ""
    @State var showAlert : Bool = false
    var body: some View {
        NavigationView {
            VStack{
                //1账号
                HStack(alignment: .center, spacing: 20) {
                    Text("账号")
                        .font(.title)
                        
                    TextField("请输入账号" , text:$account )
                        .font(.title)
                        .padding([.leading,.trailing],10)
                }
                .padding(.leading,20)
                
                //2密码
                HStack(alignment: .center, spacing: 20) {
                    Text("密码")
                        .font(.title)
                    SecureField("请输入密码" , text:$pwd )
                        .font(.title)
                        .padding([.leading,.trailing],10)
                        
                }
                .padding(.leading,20)
                
                //3 登录,
                Button {
                    if self.account.count < 6 || self.pwd.count < 6{
                        self.loginSuccess = false
                        self.showAlert = true
                        return
                    }
                    
                    // key 用来标识存储的账号   value 标识密码
                    let key = "account_" + account
                    if let value = UserDefaults.standard.object(forKey: key) as? String,value == pwd{
                        self.loginSuccess = true
                        self.showAlert = false
                    }else{
                        self.showAlert = true
                    }
                } label: {
                    Text("登录")
                        .frame(width: 200, height: 40, alignment: .center)
                        .foregroundColor(Color.white)
                        .background(Color.blue)
                }
                .padding(.top,30)
                .alert(isPresented: $showAlert) {
                    Alert(title: Text("提示"), message: Text("账号或密码错误"), dismissButton: .default(Text("OK")))
                }
              
                //4注册按钮
                NavigationLink(destination: RegisterView()) {
                    Text("注册")
                        .frame(width: 200, height: 40, alignment: .center)
                }
                .padding(.top,20)
                
                Spacer()
                
            }
            .padding(.top,100)
            .navigationBarTitle("登录",displayMode: .inline)
        }
        
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(loginSuccess: Binding.constant(false),account: Binding.constant(""))
    }
}
