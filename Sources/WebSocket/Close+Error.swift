#if os(macOS)
    
    import Foundation
    
    extension Close : LocalizedError {
        
        public var errorDescription: String? {
            return reason
        }
        
    }
    
#else

    extension Close : Error { }

#endif
