import AppKit
let size=1024
let image=NSImage(size:NSSize(width:size,height:size))
image.lockFocus()
let shell=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:200,yRadius:200)
let gradient=NSGradient(colors:[NSColor(red:0.22,green:0.19,blue:0.15,alpha:1),NSColor(red:0.055,green:0.05,blue:0.045,alpha:1)])!
gradient.draw(in:shell,angle:-90)
func card(_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ height:CGFloat,_ angle:CGFloat,_ color:NSColor) {
 NSGraphicsContext.saveGraphicsState()
 let transform=AffineTransform(translationByX:x,byY:y);(transform as NSAffineTransform).concat()
 let rotation=AffineTransform(rotationByDegrees:angle);(rotation as NSAffineTransform).concat()
 let path=NSBezierPath(roundedRect:NSRect(x:-width/2,y:-height/2,width:width,height:height),xRadius:42,yRadius:42)
 color.setFill();path.fill();NSGraphicsContext.restoreGraphicsState()
}
card(414,493,335,480,18,NSColor(red:0.32,green:0.27,blue:0.21,alpha:1))
card(525,521,335,480,4,NSColor(red:0.54,green:0.43,blue:0.31,alpha:1))
card(611,516,335,480,-12,NSColor(red:0.96,green:0.63,blue:0.36,alpha:1))
NSGraphicsContext.saveGraphicsState()
let transform=NSAffineTransform();transform.translateX(by:611,yBy:516);transform.rotate(byDegrees:-12);transform.concat()
let diamond=NSBezierPath();diamond.move(to:NSPoint(x:0,y:94));diamond.line(to:NSPoint(x:72,y:0));diamond.line(to:NSPoint(x:0,y:-94));diamond.line(to:NSPoint(x:-72,y:0));diamond.close()
NSColor(red:0.06,green:0.14,blue:0.19,alpha:1).setFill();diamond.fill()
let line=NSBezierPath(roundedRect:NSRect(x:-80,y:-170,width:160,height:13),xRadius:6,yRadius:6);line.fill()
NSGraphicsContext.restoreGraphicsState()
image.unlockFocus()
let data=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
