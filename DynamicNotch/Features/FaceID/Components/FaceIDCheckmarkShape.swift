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
        
        path.move(to: CGPoint(x: w * 0.336, y: h * 0.512))
        path.addLine(to: CGPoint(x: w * 0.463, y: h * 0.648))
        path.addLine(to: CGPoint(x: w * 0.676, y: h * 0.405))
        return path
    }
}
