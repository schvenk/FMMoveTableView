//
//  FMMoveTableView.m
//  FMFramework
//
//  Created by Florian Mielke.
//  Copyright 2012 Florian Mielke. All rights reserved.
//  

#import "FMMoveTableView.h"

/**
 * We need a little helper to cancel the current touch of the long press gesture recognizer
 * in the case the user does not tap on a row but on a section or table header
 */
@interface UIGestureRecognizer (FMUtilities)

- (void)cancelTouch;

@end


@implementation UIGestureRecognizer (FMUtilities)

- (void)cancelTouch
{
    self.enabled = NO;
    self.enabled = YES;
}

@end



@interface FMMoveTableView ()

@property (nonatomic, assign) CGPoint touchOffset;
@property (nonatomic, strong) UIView *snapShotOfMovingCell;
@property (nonatomic, strong) UILongPressGestureRecognizer *movingGestureRecognizer;

@property (nonatomic, strong) NSTimer *autoscrollTimer;
@property (nonatomic, assign) NSInteger autoscrollDistance;
@property (nonatomic, assign) NSInteger autoscrollThreshold;

@end



@implementation FMMoveTableView

@dynamic dataSource;
@dynamic delegate;



#pragma mark - View life cycle

- (void)prepareGestureRecognizer
{
	self.movingGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    self.movingGestureRecognizer.delegate = self;
	[self addGestureRecognizer:self.movingGestureRecognizer];
}


- (void)awakeFromNib
{
	[super awakeFromNib];
	
	[self prepareGestureRecognizer];
}


- (id)initWithFrame:(CGRect)frame style:(UITableViewStyle)style
{
	self = [super initWithFrame:frame style:style];
	
	if (self) {
		[self prepareGestureRecognizer];
	}
	
	return self;
}



#pragma mark - Handle gesture

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
	BOOL shouldBegin = YES;
	
	if ([gestureRecognizer isEqual:self.movingGestureRecognizer])
	{
        CGPoint touchPoint = [gestureRecognizer locationInView:self];
        NSIndexPath *touchedIndexPath = [self indexPathForRowAtPoint:touchPoint];
        shouldBegin = [self isValidIndexPath:touchedIndexPath];

		if (shouldBegin && [self.dataSource respondsToSelector:@selector(moveTableView:canMoveRowAtIndexPath:)]) {
			shouldBegin = [self.dataSource moveTableView:self canMoveRowAtIndexPath:touchedIndexPath];
		}
	}
	
	return shouldBegin;
}


- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
	switch (gestureRecognizer.state)
	{
		case UIGestureRecognizerStateBegan:
		{
			CGPoint touchPoint = [gestureRecognizer locationInView:self];
            [self prepareForMovingRowAtTouchPoint:touchPoint];
			
			break;
		}
			
		case UIGestureRecognizerStateChanged:
		{
			CGPoint touchPoint = [gestureRecognizer locationInView:self];
            [self moveSnapShotToLocation:touchPoint];
			[self maybeAutoscroll];
			
			if (![self isAutoscrolling]) {
				[self moveRowToLocation:touchPoint];
			}
			
			break;
		}
			
		case UIGestureRecognizerStateEnded:
		{
            [self finishMovingRow];
			break;
		}
			
		default:
		{
            [self cancelMovingRowIfNeeded];
			break;
		}
	}
}


- (void)prepareForMovingRowAtTouchPoint:(CGPoint)touchPoint
{
    NSIndexPath *touchedIndexPath = [self indexPathForRowAtPoint:touchPoint];
    self.initialIndexPathForMovingRow = touchedIndexPath;
    self.movingIndexPath = touchedIndexPath;

    self.snapShotOfMovingCell = [self snapShotFromRowAtMovingIndexPath];
    [self addSubview:self.snapShotOfMovingCell];

    self.touchOffset = CGPointMake(self.snapShotOfMovingCell.center.x - touchPoint.x, self.snapShotOfMovingCell.center.y - touchPoint.y);
    [self prepareAutoscrollForSnapShot];
    
    if ([self.delegate respondsToSelector:@selector(moveTableView:willMoveRowAtIndexPath:)]) {
        [self.delegate moveTableView:self willMoveRowAtIndexPath:self.movingIndexPath];
    }
}


- (void)finishMovingRow
{
    [self stopAutoscrolling];
    
    CGRect finalFrame = [self rectForRowAtIndexPath:self.movingIndexPath];
    if (CGRectEqualToRect(finalFrame, CGRectZero)) {
        return;
    }
    
    [UIView animateWithDuration:0.2
                     animations:^{
                         
                         self.snapShotOfMovingCell.frame = finalFrame;
                         self.snapShotOfMovingCell.alpha = 1.0;
                         
                     }
                     completion:^(BOOL finished) {
                         
                         if (finished)
                         {
                             [self resetSnapShot];
                             
                             if ([self.initialIndexPathForMovingRow compare:self.movingIndexPath] != NSOrderedSame) {
                                 [self.dataSource moveTableView:self moveRowFromIndexPath:self.initialIndexPathForMovingRow toIndexPath:self.movingIndexPath];
                             }
                             
                             [self resetMovingRow];
                         }
                         
                     }];
}


- (void)cancelMovingRowIfNeeded
{
    if (self.movingIndexPath != nil)
    {
        [self stopAutoscrolling];
        [self resetSnapShot];
        [self resetMovingRow];
    }
}


- (void)resetMovingRow
{
    NSIndexPath *movingIndexPath = [self.movingIndexPath copy];
    self.movingIndexPath = nil;
    self.initialIndexPathForMovingRow = nil;
    [self reloadRowsAtIndexPaths:@[movingIndexPath] withRowAnimation:UITableViewRowAnimationNone];
}


- (void)moveRowToLocation:(CGPoint)location
{
	NSIndexPath *newIndexPath = [self indexPathForRowAtPoint:location];
    if (![self canMoveToIndexPath:newIndexPath]) {
        return;
    }
    
    [self beginUpdates];
    [self deleteRowsAtIndexPaths:@[self.movingIndexPath] withRowAnimation:UITableViewRowAnimationFade];
    [self insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
    self.movingIndexPath = newIndexPath;
    [self endUpdates];
}


- (BOOL)canMoveToIndexPath:(NSIndexPath *)indexPath
{
    if (![self isValidIndexPath:indexPath]) {
        return NO;
    }
    
    if ([indexPath compare:self.movingIndexPath] == NSOrderedSame) {
        return NO;
    }
    
    if ([self.delegate respondsToSelector:@selector(moveTableView:targetIndexPathForMoveFromRowAtIndexPath:toProposedIndexPath:)])
    {
        NSIndexPath *proposedDestinationIndexPath = [self.delegate moveTableView:self targetIndexPathForMoveFromRowAtIndexPath:self.movingIndexPath toProposedIndexPath:indexPath];
        return ([indexPath compare:proposedDestinationIndexPath] == NSOrderedSame);
    }
    
    return YES;
}



#pragma mark - Index path utilities

- (BOOL)indexPathIsMovingIndexPath:(NSIndexPath *)indexPath
{
	return ([indexPath compare:self.movingIndexPath] == NSOrderedSame);
}


- (BOOL)isValidIndexPath:(NSIndexPath *)indexPath
{
    return (indexPath != nil && indexPath.section != NSNotFound && indexPath.row != NSNotFound);
}


- (NSIndexPath *)adaptedIndexPathForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.movingIndexPath == nil) {
        return indexPath;
    }
    
    CGFloat adaptedRow = NSNotFound;
    NSInteger movingRowOffset = 1;
    
    // It's the moving row so return the initial index path
    if ([indexPath compare:self.movingIndexPath] == NSOrderedSame)
    {
        indexPath = self.initialIndexPathForMovingRow;
    }
    // Moving row is still in it's inital section
    else if (self.movingIndexPath.section == self.initialIndexPathForMovingRow.section)
    {
        // 1. Index path comes after initial row or is at initial row
        // 2. Index path comes before moving row
        if (indexPath.row >= self.initialIndexPathForMovingRow.row && indexPath.row < self.movingIndexPath.row)
        {
            adaptedRow = indexPath.row + movingRowOffset;
        }
        // 1. Index path comes before initial row or is at initial row
        // 2. Index path comes after moving row
        else if (indexPath.row <= self.initialIndexPathForMovingRow.row && indexPath.row > self.movingIndexPath.row)
        {
            adaptedRow = indexPath.row - movingRowOffset;
        }
    }
    // Moving row is no longer in it's inital section
    else if (self.movingIndexPath.section != self.initialIndexPathForMovingRow.section)
    {
        // 1. Index path is in the moving rows initial section
        // 2. Index path comes after initial row or is at initial row
        if (indexPath.section == self.initialIndexPathForMovingRow.section && indexPath.row >= self.initialIndexPathForMovingRow.row)
        {
            adaptedRow = indexPath.row + movingRowOffset;
        }
        // 1. Index path is in the moving rows current section
        // 2. Index path comes before moving row
        else if (indexPath.section == self.movingIndexPath.section && indexPath.row > self.movingIndexPath.row)
        {
            adaptedRow = indexPath.row - movingRowOffset;
        }
    }
    
    // We finally need to create an adapted index path
    if (adaptedRow != NSNotFound) {
        indexPath = [NSIndexPath indexPathForRow:adaptedRow inSection:indexPath.section];
    }
    
	return indexPath;
}



#pragma mark - Snap shot

- (UIColor*)blendColor:(UIColor*)topColor overColor:(UIColor*)bottomColor {
    // TODO: This algorithm may not be quite right. See http://en.wikipedia.org/wiki/Alpha_compositing
    CGFloat r1, g1, b1, a1, r2, g2, b2, a2;
    [topColor getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [bottomColor getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    
    CGFloat alpha = a1 + a2 * (1 - a1);
    CGFloat red = (r1 * a1 + r2 * a2 * 1 - a1) / alpha;
    CGFloat green = (g1 * a1 + g2 * a2 * 1 - a1) / alpha;
    CGFloat blue = (b1 * a1 + b2 * a2 * 1 - a1) / alpha;
    
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}


- (UIView *)snapShotFromRowAtMovingIndexPath
{
    UITableViewCell<FMMoveTableViewCell>* touchedCell = (UITableViewCell<FMMoveTableViewCell> *)[self cellForRowAtIndexPath:self.movingIndexPath];
    touchedCell.selected = NO;
    touchedCell.highlighted = NO;
    UIColor* originalBackground = nil;
    if ([touchedCell respondsToSelector:@selector(backgroundColorForDraggedSnapshot)]) {
        UIColor* dragBackground = [touchedCell backgroundColorForDraggedSnapshot];
        if (dragBackground) {
            originalBackground = touchedCell.backgroundColor;
            touchedCell.backgroundColor = [self blendColor:touchedCell.backgroundColor overColor:dragBackground];
        }
    }

    UIView *snapShot = [touchedCell snapshotViewAfterScreenUpdates:YES];
    snapShot.frame = touchedCell.frame;
    snapShot.alpha = 0.95;
    snapShot.layer.shadowOpacity = 0.7;
    snapShot.layer.shadowRadius = 3.0;
    snapShot.layer.shadowOffset = CGSizeZero;
    snapShot.layer.shadowPath = [[UIBezierPath bezierPathWithRect:snapShot.layer.bounds] CGPath];

    if (originalBackground) {
        touchedCell.backgroundColor = originalBackground;
    }
    
    [touchedCell prepareForMove];
    
    return snapShot;
}


- (void)moveSnapShotToLocation:(CGPoint)touchPoint
{
    CGPoint currentCenter = self.snapShotOfMovingCell.center;
    self.snapShotOfMovingCell.center = CGPointMake(currentCenter.x, touchPoint.y + self.touchOffset.y);
}


- (void)resetSnapShot
{
    [self.snapShotOfMovingCell removeFromSuperview];
    self.snapShotOfMovingCell = nil;
}



#pragma mark - Autoscrolling

- (void)prepareAutoscrollForSnapShot
{
    self.autoscrollThreshold = CGRectGetHeight(self.snapShotOfMovingCell.frame) * 0.6;
    self.autoscrollDistance = 0;
}


- (void)maybeAutoscroll
{
    [self determineAutoscrollDistanceForSnapShot];
    
    if (self.autoscrollDistance == 0)
	{
        [self.autoscrollTimer invalidate];
        self.autoscrollTimer = nil;
    } 
    else if (self.autoscrollTimer == nil)
	{
        self.autoscrollTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0) target:self selector:@selector(autoscrollTimerFired:) userInfo:nil repeats:YES];
    }
}


- (void)determineAutoscrollDistanceForSnapShot
{
    self.autoscrollDistance = 0;
    
	// Check for autoscrolling
	// 1. The content size is bigger than the frame's
	// 2. The snap shot is still inside the table view's bounds
    if ([self canScroll] && CGRectIntersectsRect(self.snapShotOfMovingCell.frame, self.bounds))
	{
		CGPoint touchLocation = [self.movingGestureRecognizer locationInView:self];
		touchLocation.y += self.touchOffset.y;

        CGFloat distanceToTopEdge = touchLocation.y - CGRectGetMinY(self.bounds);
        CGFloat distanceToBottomEdge = CGRectGetMaxY(self.bounds) - touchLocation.y;

        if (distanceToTopEdge < self.autoscrollThreshold)
		{
            self.autoscrollDistance = [self autoscrollDistanceForProximityToEdge:distanceToTopEdge] * -1;
        }
		else if (distanceToBottomEdge < self.autoscrollThreshold)
		{
            self.autoscrollDistance = [self autoscrollDistanceForProximityToEdge:distanceToBottomEdge];
        }
    }
}


- (CGFloat)autoscrollDistanceForProximityToEdge:(CGFloat)proximity
{
    return ceilf((self.autoscrollThreshold - proximity) / 5.0);
}


- (void)autoscrollTimerFired:(NSTimer *)timer
{
    [self legalizeAutoscrollDistance];
    
    CGPoint contentOffset = self.contentOffset;
    contentOffset.y += self.autoscrollDistance;
    self.contentOffset = contentOffset;

    CGRect frame = self.snapShotOfMovingCell.frame;
    frame.origin.y += self.autoscrollDistance;
    self.snapShotOfMovingCell.frame = frame;
	
	CGPoint touchLocation = [self.movingGestureRecognizer locationInView:self];
	[self moveRowToLocation:touchLocation];
}


- (void)legalizeAutoscrollDistance
{
    CGFloat minimumLegalDistance = self.contentOffset.y * -1.0;
    CGFloat maximumLegalDistance = self.contentSize.height - (CGRectGetHeight(self.frame) + self.contentOffset.y);
    self.autoscrollDistance = MAX(self.autoscrollDistance, minimumLegalDistance);
    self.autoscrollDistance = MIN(self.autoscrollDistance, maximumLegalDistance);
}


- (void)stopAutoscrolling
{
    self.autoscrollDistance = 0.0;
	[self.autoscrollTimer invalidate];
	self.autoscrollTimer = nil;
}


- (BOOL)isAutoscrolling
{
    return (self.autoscrollDistance != 0);
}


- (BOOL)canScroll
{
    return (CGRectGetHeight(self.frame) < self.contentSize.height);
}

@end