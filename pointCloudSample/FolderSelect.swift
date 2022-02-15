//
// Created by Zitong Zhan on 11/15/21.
// Copyright (c) 2021 Apple. All rights reserved.
//

import Foundation
import SwiftUI
import MetalKit
import Metal
import MobileCoreServices

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selected_folder: URL

    func makeCoordinator() -> DocumentPickerCoordinator {
        return DocumentPickerCoordinator(fileContent: $selected_folder)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
        let controller: UIDocumentPickerViewController
        if #available(iOS 14, *) {
            controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        } else {
            controller = UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String], in: .open)
        }
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController:UIDocumentPickerViewController,
                            context: UIViewControllerRepresentableContext<DocumentPicker>){}

    class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate,
            UINavigationControllerDelegate{
        @Binding var selected_url: URL
        init(fileContent: Binding<URL>) {
            _selected_url = fileContent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            let fileURL = urls[0]
            self.selected_url = fileURL
            print("document picker return url" + fileURL.absoluteString)
        }
    }
}