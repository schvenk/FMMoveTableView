//
//  FMMoveTableViewCell.h
//  stky
//
//  Created by Dave Feldman on 5/15/14.
//
//

#import <Foundation/Foundation.h>

@protocol FMMoveTableViewCell <NSObject>
@required
- (void)prepareForMove;
- (UIColor*)backgroundColorForDraggedSnapshot;
@end
