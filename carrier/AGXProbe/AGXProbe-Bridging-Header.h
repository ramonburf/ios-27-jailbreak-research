//
//  AGXProbe-Bridging-Header.h
//  AGXProbe
//
//  iOS ships IOKit.framework headers but no Swift module for it, so expose
//  the C API to Swift through a bridging header instead of `import IOKit`.
//

#import <IOKit/IOKitLib.h>
