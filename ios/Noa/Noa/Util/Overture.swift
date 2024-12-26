//
//  Overture.swift
//  Noa
//
//  Created by Adi Ayyakad on 12/26/24.
//

import Foundation

//func curry<A, B>(_ block: @escaping (A, B) -> Void) -> (A) -> (B) -> Void {
//    { a in { b in block(a, b) } }
//}

func curry<A, B, C>(_ block: @escaping (A, B) -> C) -> (A) -> (B) -> C {
    { a in { b in block(a, b) } }
}

func flip<A, B>(_ block: @escaping (A, B) -> Void) -> (B, A) -> Void {
    { b, a in block(a, b) }
}

func flip<A, B>(_ block: @escaping (A) -> (B) -> Void) -> (B) -> (A) -> Void {
    { b in { a in block(a)(b) } }
}
