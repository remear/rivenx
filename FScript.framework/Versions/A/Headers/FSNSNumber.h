/* FSNSNumber.h Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.       */  

#import <Foundation/Foundation.h>

@class FSBoolean, Number, Block, Array;

@interface NSObject(FSNSNumber)

- (NSNumber *)abs;
- (NSNumber *)arcCos;
- (NSNumber *)arcSin;
- (NSNumber *)arcTan;
- (NSDate *)asDate;
- (FSBoolean *)between:(NSNumber *)a and:(NSNumber *)b;
- (NSNumber *)bitAnd:(NSNumber *)operand;
- (NSNumber *)bitOr:(NSNumber *)operand;
- (NSNumber *)bitXor:(NSNumber *)operand;
- (NSNumber *)ceiling;
- (NSNumber *)clone;
- (NSNumber *)cos;
- (NSNumber *)cosh; 
- (NSNumber *)exp; 
- (NSNumber *)floor;  
- (NSNumber *)fractionPart;
- (NSNumber *)integerPart;
- (Array *)iota;    // APL iota. Index origin = 0
- (NSNumber *)ln;
- (NSNumber *)log;
- (NSNumber *)max:(NSNumber *)operand;
- (NSNumber *)min:(NSNumber *)operand;
- (NSNumber *)negated;
- (NSNumber *)operator_asterisk:(NSNumber *)operand;
- (NSNumber *)operator_hyphen:(NSNumber *)operand;
- (NSPoint)operator_less_greater:(NSNumber *)operand; 
- (NSNumber *)operator_plus:(id)operand;
- (NSNumber *)operator_slash:(NSNumber *)operand;
- (FSBoolean *)operator_greater:(NSNumber *)operand;
- (FSBoolean *)operator_greater_equal:(NSNumber *)operand;
- (FSBoolean *)operator_less:(id)operand;  
- (FSBoolean *)operator_less_equal:(NSNumber *)operand;
- (NSNumber *)raisedTo:(NSNumber *)operand;
- (NSNumber *)random;
- (Array *)random:(Number *)operand;
- (void)seedRandom;
- (NSNumber *)rem:(NSNumber *)operand;
- (NSNumber *)sin;
- (NSNumber *)sign; 
- (NSNumber *)sinh;
- (NSNumber *)sqrt;
- (NSNumber *)tan;
- (NSNumber *)tanh;
- (NSNumber *)truncated;
- (NSString *)unicharToString;
- (void)timesRepeat:(Block *)operation;
- (void)to:(NSNumber *)stop do:(Block *)operation;
- (void)to:(NSNumber *)stop by:(NSNumber *)step do:(Block *)operation;

@end
