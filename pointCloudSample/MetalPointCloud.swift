/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 A class that represents a point cloud.
 */

import Foundation
import SwiftUI
import MetalKit
import Metal
import MobileCoreServices

func makePerspectiveMatrixProjection(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
    let yProj: Float = 1.0 / tanf(fovyRadians * 0.5)
    let xProj: Float = yProj / aspect
    let zProj: Float = farZ / (farZ - nearZ)
    let proj: simd_float4x4 = simd_float4x4(SIMD4<Float>(xProj, 0, 0, 0),
                                            SIMD4<Float>(0, yProj, 0, 0),
                                            SIMD4<Float>(0, 0, zProj, 1.0),
                                            SIMD4<Float>(0, 0, -zProj * nearZ, 0))
    return proj
}
//- Tag: CoordinatorPointCloud
final class CoordinatorPointCloud: MTKCoordinator {
    var account: String
    var arData: ARProvider
    var depthState: MTLDepthStencilState!
    @Binding var confSelection: Int
    @Binding var scaleMovement: Float
    
    // zitong: a save switch
    @Binding var record_flag: Bool
    @Binding var folder_path: URL
    var frameNum = 0
    var depth_buffer_array:[Array<Float32>]=[]
    var depth_confid_array:[Array<Int8>]=[]
    var video_images:[UIImage]=[]
    var pre_time_stamp: Double = -1
    
    var staticAngle: Float = 0.0
    var staticInc: Float = 0.02
    enum CameraModes {
        case quarterArc
        case sidewaysMovement
    }
    var currentCameraMode: CameraModes
    
    //    init(mtkView: MTKView, arData: ARProvider, confSelection: Binding<Int>, scaleMovement: Binding<Float>) {
    //        self.arData = arData
    //        self.currentCameraMode = .sidewaysMovement
    //        self._confSelection = confSelection
    //        self._scaleMovement = scaleMovement
    //        super.init(content: arData.depthContent, view: mtkView)
    //    }
    
    // zitong
    init(account:String,mtkView: MTKView, arData: ARProvider, confSelection: Binding<Int>, scaleMovement: Binding<Float>,
         record_flag: Binding<Bool> = .constant(true), folder_path: Binding<URL> = .constant(URL(string: "1")!)) {
        self.account = account
        self.arData = arData
        self.currentCameraMode = .sidewaysMovement
        self._confSelection = confSelection
        self._scaleMovement = scaleMovement
        self._record_flag = record_flag
        self._folder_path = folder_path
        super.init(content: arData.depthContent, view: mtkView)
    }
    
    override func prepareFunctions() {
        guard let metalDevice = view.device else { fatalError("Expected a Metal device.") }
        do {
            let library = metalDevice.makeDefaultLibrary()
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.vertexFunction = library!.makeFunction(name: "pointCloudVertexShader")
            pipelineDescriptor.fragmentFunction = library!.makeFunction(name: "pointCloudFragmentShader")
            pipelineDescriptor.vertexDescriptor = createPlaneMetalVertexDescriptor()
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            
            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.isDepthWriteEnabled = true
            depthDescriptor.depthCompareFunction = .less
            depthState = metalDevice.makeDepthStencilState(descriptor: depthDescriptor)
        } catch {
            print("Unexpected error: \(error).")
        }
    }
    func calcCurrentPMVMatrix(viewSize: CGSize) -> matrix_float4x4 {
        let projection: matrix_float4x4 = makePerspectiveMatrixProjection(fovyRadians: Float.pi / 2.0,
                                                                          aspect: Float(viewSize.width) / Float(viewSize.height),
                                                                          nearZ: 10.0, farZ: 8000.0)
        
        var orientationOrig: simd_float4x4 = simd_float4x4()
        // Since the camera stream is rotated clockwise, rotate it back.
        orientationOrig.columns.0 = [0, -1, 0, 0]
        orientationOrig.columns.1 = [-1, 0, 0, 0]
        orientationOrig.columns.2 = [0, 0, 1, 0]
        orientationOrig.columns.3 = [0, 0, 0, 1]
        
        var translationOrig: simd_float4x4 = simd_float4x4()
        // Move the object forward to enhance visibility.
        translationOrig.columns.0 = [1, 0, 0, 0]
        translationOrig.columns.1 = [0, 1, 0, 0]
        translationOrig.columns.2 = [0, 0, 1, 0]
        translationOrig.columns.3 = [0, 0, +0, 1]
        
        if currentCameraMode == .quarterArc {
            // Limit camera rotation to a quarter arc, to and fro, while aimed
            // at the center.
            if staticAngle <= 0 {
                staticInc = -staticInc
            }
            if staticAngle > 1.2 {
                staticInc = -staticInc
            }
        }
        
        staticAngle += staticInc
        
        let sinf = sin(staticAngle)
        let cosf = cos(staticAngle)
        let sinsqr = sinf * sinf
        let cossqr = cosf * cosf
        
        var translationCamera: simd_float4x4 = simd_float4x4()
        translationCamera.columns.0 = [1, 0, 0, 0]
        translationCamera.columns.1 = [0, 1, 0, 0]
        translationCamera.columns.2 = [0, 0, 1, 0]
        
        var cameraRotation: simd_quatf
        
        switch currentCameraMode {
        case .quarterArc:
            // Rotate the point cloud 1/4 arc.
            translationCamera.columns.3 = [0, -1500 * sinf, -1500 * scaleMovement * sinf, 1]
            cameraRotation = simd_quatf(angle: staticAngle, axis: SIMD3(x: -1, y: 0, z: 0))
        case .sidewaysMovement:
            // Randomize the camera scale.
            translationCamera.columns.3 = [150 * sinf, -150 * cossqr, -150 * scaleMovement * sinsqr, 1]
            // Randomize the camera movement.
            cameraRotation = simd_quatf(angle: staticAngle, axis: SIMD3(x: -sinsqr / 3, y: -cossqr / 3, z: 0))
        }
        let rotationMatrix: matrix_float4x4 = matrix_float4x4(cameraRotation)
        let pmv = projection * rotationMatrix * translationCamera * translationOrig * orientationOrig
        return pmv
    }
    override func draw(in view: MTKView) {
        content = arData.depthContent
        let confidence = (arData.isToUpsampleDepth) ? arData.upscaledConfidence:arData.confidenceContent
        guard arData.lastArData != nil else {
            print("Depth data not available; skipping a draw.")
            return
        }
        // depth data is in self.arData.arReceiver.arData.depthImage
        // zitong
        let colorImage = arData.lastArData!.colorImage!
        let depthImage = arData.lastArData!.depthImage!
        let cfidtImage = arData.lastArData!.confidenceImage!
        let timestamp = arData.lastArData!.timestamp
        
        if self.record_flag{ //  && (timestamp != 0) && (timestamp != pre_time_stamp)
            print("record on! Frame num " + String(frameNum) + " " + String(timestamp) + folder_path.absoluteString)
            frameNum += 1
            
            // append everything
            //            self.depth_confid_array.append(self.convertDepthDataI8(depthFrame: colorImage))
            let depthImageBinary = (self.convertDepthDataF32(depthFrame: depthImage))
            let cfidtImageBinary = (self.convertDepthDataI8(depthFrame: cfidtImage))
            
            //            let colorImgUI = pixelBufferToUIImage(pixelBuffer: colorImage)
            let colorImgUI = createImage(colorImage)!
            self.video_images.append(colorImgUI)
            
            pre_time_stamp = timestamp
            //            self.video_images.append(colorImgUI)
            //            return
            //        } else {
            if true {// write everything
                let shouldStopAccessing = folder_path.startAccessingSecurityScopedResource()
                defer {
                    if shouldStopAccessing {
                        folder_path.stopAccessingSecurityScopedResource()
                    }
                }
                var coordinatedError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: folder_path, error: &coordinatedError)
                {
                    (folderURL) in
                    do {
                        //                    let keys : [URLResourceKey] = [.nameKey]
                        //                    let fileList = try FileManager.default.enumerator(at: folderURL,
                        //                            includingPropertiesForKeys: keys)
                        //                    for case let file as URL in fileList! {
                        //                        print(file.absoluteString)
                        //                    }
                        
                        // above code is used to enumerate dir
                        // write imgs
                        let depth_dump_path = folderURL.appendingPathComponent( (String(timestamp) + "depth_array.data") )
                        let cfidt_dump_path = folderURL.appendingPathComponent( (String(timestamp) + "confid_array.data") )
                        let color_dump_path = folderURL.appendingPathComponent( (String(timestamp) + "color_image.png") )
                        let device_dump_path = folderURL.appendingPathComponent( (String(timestamp) + "deviceInfo.json") )
                        
                        let depth_pointer = UnsafeBufferPointer(
                            start: depthImageBinary,
                            count: CVPixelBufferGetWidth(depthImage)*CVPixelBufferGetHeight(depthImage))
                        let depth_data = Data(buffer:depth_pointer)
                        try depth_data.write(to: depth_dump_path)
                        
                        let cfidt_pointer = UnsafeBufferPointer(
                            start: cfidtImageBinary,
                            count: CVPixelBufferGetWidth(cfidtImage)*CVPixelBufferGetHeight(cfidtImage))
                        let cfidt_data = Data(buffer:cfidt_pointer)
                        try cfidt_data.write(to: cfidt_dump_path)
                        
                        let pngData = colorImgUI.pngData()
                        try pngData?.write(to: color_dump_path)
                        // 写账号和登录数据
                        let deviceName = UIDevice.current.name
                        let deviceInfoData = try! JSONSerialization.data(withJSONObject: ["account":account,"deviceName":deviceName], options: .fragmentsAllowed)
                        //let url = URL(fileURLWithPath: filePath2)
                        try deviceInfoData.write(to: device_dump_path)
                        
                    } catch  {
                        //print("Error while reading protected folder")
                        print("Error: \(error.localizedDescription.debugDescription)")
                    }
                }
                self.record_flag=false
            }
        }
        
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }
        guard let passDescriptor = view.currentRenderPassDescriptor else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setDepthStencilState(depthState)
        encoder.setVertexTexture(content.texture, index: 0)
        encoder.setVertexTexture(confidence.texture, index: 1)
        encoder.setVertexTexture(arData.colorYContent.texture, index: 2)
        encoder.setVertexTexture(arData.colorCbCrContent.texture, index: 3)
        
        
        // Camera-intrinsics units are in full camera-resolution pixels.
        var cameraIntrinsics = arData.lastArData!.cameraIntrinsics
        let depthResolution = simd_float2(x: Float(content.texture!.width), y: Float(content.texture!.height))
        let scaleRes = simd_float2(x: Float( arData.lastArData!.cameraResolution.width) / depthResolution.x,
                                   y: Float(arData.lastArData!.cameraResolution.height) / depthResolution.y )
        cameraIntrinsics[0][0] /= scaleRes.x
        cameraIntrinsics[1][1] /= scaleRes.y
        
        cameraIntrinsics[2][0] /= scaleRes.x
        cameraIntrinsics[2][1] /= scaleRes.y
        var pmv = calcCurrentPMVMatrix(viewSize: CGSize(width: view.frame.width, height: view.frame.height))
        encoder.setVertexBytes(&pmv, length: MemoryLayout<matrix_float4x4>.stride, index: 0)
        encoder.setVertexBytes(&cameraIntrinsics, length: MemoryLayout<matrix_float3x3>.stride, index: 1)
        encoder.setVertexBytes(&confSelection, length: MemoryLayout<Int>.stride, index: 2)
        encoder.setRenderPipelineState(pipelineState)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Int(depthResolution.x * depthResolution.y))
        encoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    @available(iOS 14.0, *)
    func convertDepthDataF32(depthFrame: CVPixelBuffer) -> Array<Float32>{
        let width = CVPixelBufferGetWidth(depthFrame)
        let height = CVPixelBufferGetHeight(depthFrame)
        
        CVPixelBufferLockBaseAddress(depthFrame, .readOnly)
        
        let base_addr = CVPixelBufferGetBaseAddress(depthFrame)
        assert (kCVPixelFormatType_DepthFloat32 == CVPixelBufferGetPixelFormatType(depthFrame))
        let res = Array(UnsafeBufferPointer(start: base_addr!.bindMemory(to: Float32.self, capacity: height * width), count: height * width))
        CVPixelBufferUnlockBaseAddress(depthFrame, .readOnly)
        return res
    }
    
    func convertDepthDataI8(depthFrame: CVPixelBuffer) -> Array<Int8>{
        let width = CVPixelBufferGetWidth(depthFrame)
        let height = CVPixelBufferGetHeight(depthFrame)
        
        CVPixelBufferLockBaseAddress(depthFrame, .readOnly)
        
        let base_addr = CVPixelBufferGetBaseAddress(depthFrame)
        //        print(depthFrame.pixelFormatName())
        assert (kCVPixelFormatType_OneComponent8 == CVPixelBufferGetPixelFormatType(depthFrame))
        let res = Array(UnsafeBufferPointer(start: base_addr!.bindMemory(to: Int8.self, capacity: height * width), count: height * width))
        CVPixelBufferUnlockBaseAddress(depthFrame, .readOnly)
        return res
    }
    
    //    func pixelBuffer2UIImage (inputPixelBuffer: CVPixelBuffer) -> UIImage?{
    //        let depth_ciimage = CIImage(cvPixelBuffer: inputPixelBuffer) // depth cvPixelBuffer
    //
    //        // this could also be made into an extension
    //        func cgImage(from ciImage: CIImage) -> CGImage? {
    //            let context = CIContext(options: nil)
    //            return context.createCGImage(ciImage, from: ciImage.extent)
    //        }
    //
    //        guard let cgImage = cgImage(from: depth_ciimage) else {
    //            return nil
    //        }
    //        return UIImage(cgImage: cgImage)
    //    }
    func pixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let uiImage = UIImage(cgImage: cgImage!)
        return uiImage
    }
}
//- Tag: MetalPointCloud
struct MetalPointCloud: UIViewRepresentable {
    var account: String
    var mtkView: MTKView
    var arData: ARProvider
    @Binding var confSelection: Int
    @Binding var scaleMovement: Float
    
    @Binding var record_switch_var: Bool
    @Binding var folder_path: URL
    
    func makeCoordinator() -> CoordinatorPointCloud {
        return CoordinatorPointCloud(account:account, mtkView: mtkView, arData: arData,
                                     confSelection: $confSelection, scaleMovement: $scaleMovement,
                                     record_flag: $record_switch_var, folder_path: $folder_path)
    }
    func makeUIView(context: UIViewRepresentableContext<MetalPointCloud>) -> MTKView {
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.backgroundColor = context.environment.colorScheme == .dark ? .black : .white
        mtkView.isOpaque = true
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.drawableSize = mtkView.frame.size
        mtkView.enableSetNeedsDisplay = false
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm
        return mtkView
    }
    
    // `UIViewRepresentable` requires this implementation; however, the sample
    // app doesn't use it. Instead, `MTKView.delegate` handles display updates.
    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MetalPointCloud>) {
        
    }
}

extension CVPixelBuffer {
    func pixelFormatName() -> String {
        let p = CVPixelBufferGetPixelFormatType(self)
        switch p {
        case kCVPixelFormatType_1Monochrome:                   return "kCVPixelFormatType_1Monochrome"
        case kCVPixelFormatType_2Indexed:                      return "kCVPixelFormatType_2Indexed"
        case kCVPixelFormatType_4Indexed:                      return "kCVPixelFormatType_4Indexed"
        case kCVPixelFormatType_8Indexed:                      return "kCVPixelFormatType_8Indexed"
        case kCVPixelFormatType_1IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_1IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_2IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_2IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_4IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_4IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_8IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_8IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_16BE555:                       return "kCVPixelFormatType_16BE555"
        case kCVPixelFormatType_16LE555:                       return "kCVPixelFormatType_16LE555"
        case kCVPixelFormatType_16LE5551:                      return "kCVPixelFormatType_16LE5551"
        case kCVPixelFormatType_16BE565:                       return "kCVPixelFormatType_16BE565"
        case kCVPixelFormatType_16LE565:                       return "kCVPixelFormatType_16LE565"
        case kCVPixelFormatType_24RGB:                         return "kCVPixelFormatType_24RGB"
        case kCVPixelFormatType_24BGR:                         return "kCVPixelFormatType_24BGR"
        case kCVPixelFormatType_32ARGB:                        return "kCVPixelFormatType_32ARGB"
        case kCVPixelFormatType_32BGRA:                        return "kCVPixelFormatType_32BGRA"
        case kCVPixelFormatType_32ABGR:                        return "kCVPixelFormatType_32ABGR"
        case kCVPixelFormatType_32RGBA:                        return "kCVPixelFormatType_32RGBA"
        case kCVPixelFormatType_64ARGB:                        return "kCVPixelFormatType_64ARGB"
        case kCVPixelFormatType_48RGB:                         return "kCVPixelFormatType_48RGB"
        case kCVPixelFormatType_32AlphaGray:                   return "kCVPixelFormatType_32AlphaGray"
        case kCVPixelFormatType_16Gray:                        return "kCVPixelFormatType_16Gray"
        case kCVPixelFormatType_30RGB:                         return "kCVPixelFormatType_30RGB"
        case kCVPixelFormatType_422YpCbCr8:                    return "kCVPixelFormatType_422YpCbCr8"
        case kCVPixelFormatType_4444YpCbCrA8:                  return "kCVPixelFormatType_4444YpCbCrA8"
        case kCVPixelFormatType_4444YpCbCrA8R:                 return "kCVPixelFormatType_4444YpCbCrA8R"
        case kCVPixelFormatType_4444AYpCbCr8:                  return "kCVPixelFormatType_4444AYpCbCr8"
        case kCVPixelFormatType_4444AYpCbCr16:                 return "kCVPixelFormatType_4444AYpCbCr16"
        case kCVPixelFormatType_444YpCbCr8:                    return "kCVPixelFormatType_444YpCbCr8"
        case kCVPixelFormatType_422YpCbCr16:                   return "kCVPixelFormatType_422YpCbCr16"
        case kCVPixelFormatType_422YpCbCr10:                   return "kCVPixelFormatType_422YpCbCr10"
        case kCVPixelFormatType_444YpCbCr10:                   return "kCVPixelFormatType_444YpCbCr10"
        case kCVPixelFormatType_420YpCbCr8Planar:              return "kCVPixelFormatType_420YpCbCr8Planar"
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:     return "kCVPixelFormatType_420YpCbCr8PlanarFullRange"
        case kCVPixelFormatType_422YpCbCr_4A_8BiPlanar:        return "kCVPixelFormatType_422YpCbCr_4A_8BiPlanar"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:  return "kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange"
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:   return "kCVPixelFormatType_420YpCbCr8BiPlanarFullRange"
        case kCVPixelFormatType_422YpCbCr8_yuvs:               return "kCVPixelFormatType_422YpCbCr8_yuvs"
        case kCVPixelFormatType_422YpCbCr8FullRange:           return "kCVPixelFormatType_422YpCbCr8FullRange"
        case kCVPixelFormatType_OneComponent8:                 return "kCVPixelFormatType_OneComponent8"
        case kCVPixelFormatType_TwoComponent8:                 return "kCVPixelFormatType_TwoComponent8"
        case kCVPixelFormatType_30RGBLEPackedWideGamut:        return "kCVPixelFormatType_30RGBLEPackedWideGamut"
        case kCVPixelFormatType_OneComponent16Half:            return "kCVPixelFormatType_OneComponent16Half"
        case kCVPixelFormatType_OneComponent32Float:           return "kCVPixelFormatType_OneComponent32Float"
        case kCVPixelFormatType_TwoComponent16Half:            return "kCVPixelFormatType_TwoComponent16Half"
        case kCVPixelFormatType_TwoComponent32Float:           return "kCVPixelFormatType_TwoComponent32Float"
        case kCVPixelFormatType_64RGBAHalf:                    return "kCVPixelFormatType_64RGBAHalf"
        case kCVPixelFormatType_128RGBAFloat:                  return "kCVPixelFormatType_128RGBAFloat"
        case kCVPixelFormatType_14Bayer_GRBG:                  return "kCVPixelFormatType_14Bayer_GRBG"
        case kCVPixelFormatType_14Bayer_RGGB:                  return "kCVPixelFormatType_14Bayer_RGGB"
        case kCVPixelFormatType_14Bayer_BGGR:                  return "kCVPixelFormatType_14Bayer_BGGR"
        case kCVPixelFormatType_14Bayer_GBRG:                  return "kCVPixelFormatType_14Bayer_GBRG"
        default: return "UNKNOWN"
        }
    }
}
