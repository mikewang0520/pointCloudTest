//
//  RegisterView.swift
//  pointCloudSample
//
//  Created by apple on 2022/1/31.
//  Copyright © 2022 Apple. All rights reserved.
//

import SwiftUI

struct RegisterView: View {
    @State var account : String = ""
    @State var pwd : String = ""
    @State var showAlert : Bool = false
    @State var alertMsg: String = ""
    var body: some View {
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
                    self.alertMsg = "请输入正确的账号和密码位数"
                    self.showAlert = true
                    return
                }
                
                // key 用来标识存储的账号   value 标识密码
                let key = "account_" + account
                if let _ = UserDefaults.standard.object(forKey: key) as? String{
                    // 根据账号key能取到数据,说明已经注册过
                    self.alertMsg = "注册失败,账号已存在"
                }else{
                    UserDefaults.standard.set(pwd, forKey: key)
                    self.alertMsg = "注册成功"
                }
                self.showAlert = true
            } label: {
                Text("立即注册")
                    .frame(width: 200, height: 40, alignment: .center)
                    .foregroundColor(Color.white)
                    .background(Color.blue)
            }
            .padding(.top,30)
            .alert(isPresented: $showAlert) {
                Alert(title: Text("提示"), message: Text(alertMsg), dismissButton: .default(Text("OK")))
            }

            
            
            Spacer()
            
        }
        .padding(.top,100)
        .navigationBarTitle("注册",displayMode: .inline)
    }
}

struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        RegisterView()
    }
}
