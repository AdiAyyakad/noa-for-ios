//
//  SetExtensions.swift
//  Noa
//
//  Created by Adi Ayyakad on 3/19/25.
//

import Foundation

func +<E: Hashable>(lhs: Set<E>, rhs: E) -> Set<E> {
    lhs.union([rhs])
}
