//
//  SwiftRURLProtocol.swift
//  SwiftR
//
//  Created by Adam Hartford on 6/3/15.
//  Copyright (c) 2015 Adam Hartford. All rights reserved.
//

import Foundation

class SwiftRURLProtocol: NSURLProtocol {
   
    // TODO
    
    override class func canonicalRequestForRequest(request: NSURLRequest) -> NSURLRequest {
        return request
    }
    
    override class func canInitWithRequest(request: NSURLRequest) -> Bool {
        return false
    }
    
}
