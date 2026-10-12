//
//  FaceIDCheckmarkShape.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 10/11/26.
//

import SwiftUI

struct FaceIDCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.315, y: h * 0.515))
        path.addLine(to: CGPoint(x: w * 0.455, y: h * 0.655))
        path.addLine(to: CGPoint(x: w * 0.705, y: h * 0.365))
        return path
    }
}
