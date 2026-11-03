import Foundation
import Vision
import CoreImage
import ImageIO
let args=CommandLine.arguments
let input=URL(fileURLWithPath:args[1]),out=URL(fileURLWithPath:args[2],isDirectory:true)
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let request=VNGenerateForegroundInstanceMaskRequest()
let handler=VNImageRequestHandler(url:input,options:[:])
try handler.perform([request])
guard let observation=request.results?.first else { fatalError("No instance observations") }
let context=CIContext(options:[.useSoftwareRenderer:true])
for id in observation.allInstances {
 let buffer=try observation.generateScaledMaskForImage(forInstances:IndexSet(integer:id),from:handler)
 let image=CIImage(cvPixelBuffer:buffer)
 guard let cg=context.createCGImage(image,from:image.extent) else {fatalError("Mask conversion failed")}
 let file=out.appendingPathComponent("instance-\(id).png")
 guard let destination=CGImageDestinationCreateWithURL(file as CFURL,"public.png" as CFString,1,nil) else {fatalError("Mask destination failed")}
 CGImageDestinationAddImage(destination,cg,nil)
 guard CGImageDestinationFinalize(destination) else {fatalError("Mask export failed")}
 print("instance \(id): \(cg.width)x\(cg.height)")
}
