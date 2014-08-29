//
//  mAEditorViewController.m
//  miniAudicle
//
//  Created by Spencer Salazar on 3/26/14.
//
//

#import "mAEditorViewController.h"
#import "mATextView.h"
#import "miniAudicle.h"
#import "mAChucKController.h"
#import "mAMasterViewController.h"
#import "mADetailItem.h"
#import "mAAppDelegate.h"
#import "mADocumentManager.h"
#import "NSString+NSString_Lines.h"
#import "NSString+STLString.h"
#import "mAAutocomplete.h"
#import "mATextCompletionView.h"


@interface NSString (CharacterEnumeration)

- (void)enumerateCharacters:(BOOL (^)(int pos, unichar c))block
               fromPosition:(NSInteger)index
                    reverse:(BOOL)reverse;
- (void)enumerateCharacters:(BOOL (^)(int pos, unichar c))block;

@end

@interface UITextView (Ranges)

- (UITextRange *)textRangeFromRange:(NSRange)range;
//- (NSRange)rangeFromTextRange:(UITextRange *)textRange;

@end


@interface mAEditorViewController ()
{
    NSRange _errorRange;
    BOOL _lockAutoFormat;
    mATextCompletionView *_textCompletionView;
}

@property (strong, nonatomic) mATextView * textView;
@property (strong, nonatomic) UIView * otfToolbar;

@property (strong, nonatomic) UIPopoverController * popover;
@property (strong, nonatomic) mATitleEditorController * titleEditor;

- (NSDictionary *)defaultTextAttributes;
- (NSDictionary *)errorTextAttributes;
- (void)configureView;

- (int)indentationForTextPosition:(int)position
                     bracketLevel:(int)bracketLevel
                       parenLevel:(int)parenLevel;
- (void)showCompletions:(NSArray *)completions forTextRange:(NSRange)range;
- (void)hideCompletions;

@end

@implementation mAEditorViewController

- (void)setShowOTFToolbar:(BOOL)showOTFToolbar
{
    if(!showOTFToolbar)
    {
        [self.otfToolbar removeFromSuperview];
        self.textView.frame = self.view.bounds;
    }
    else
    {
        [self.view addSubview:self.otfToolbar];
        CGRect rect = self.view.bounds;
        rect.origin.y += self.otfToolbar.frame.size.height;
        rect.size.height -= self.otfToolbar.frame.size.height;
        self.textView.frame = rect;
    }
}

- (BOOL)showOTFToolbar
{
    return self.otfToolbar.superview != nil;
}

- (NSDictionary *)defaultTextAttributes
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [UIFont fontWithName:@"Menlo" size:14], NSFontAttributeName,
            nil];
}

- (NSDictionary *)errorTextAttributes
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [UIColor colorWithRed:1 green:0 blue:0 alpha:0.5], NSBackgroundColorAttributeName,
            nil];
}


#pragma mark - Managing the detail item

- (void)setDetailItem:(id)newDetailItem
{
    if(_detailItem != newDetailItem)
    {
        if(_detailItem)
        {
            // save text
            [self saveScript];
            [[mAAppDelegate appDelegate] saveScripts];
        }
        
        _detailItem = newDetailItem;
        
        self.textView.errorMessage = nil;
        self.textView.errorLine = -1;
        
        // Update the view.
        [self configureView];
    }
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        
        self.titleButton = [[UIBarButtonItem alloc] initWithTitle:@""
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(editTitle:)];
        _lockAutoFormat = NO;
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        // Custom initialization
        
        self.titleButton = [[UIBarButtonItem alloc] initWithTitle:@""
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(editTitle:)];
        _lockAutoFormat = NO;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    _errorRange = NSMakeRange(NSNotFound, 0);
    
    self.textView.font = [UIFont fontWithName:@"Menlo" size:14];
    
    self.textView.inputAccessoryView = self.keyboardAccessory.view;
    self.keyboardAccessory.delegate = self;
    
    self.textView.textStorage.delegate = self;
    
    _textCompletionView = [[mATextCompletionView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
    
    [self configureView];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self.textView becomeFirstResponder];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)configureView
{
    // Update the user interface for the detail item.
    
    if (self.detailItem)
    {
        self.titleButton.title = self.detailItem.title;
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:self.detailItem.text
                                                                                 attributes:[self defaultTextAttributes]];
        [[mASyntaxHighlighting sharedHighlighter] colorString:text range:NSMakeRange(0, [text length]-1) colorer:nil];
        
        _lockAutoFormat = YES;
        self.textView.attributedText = text;
        _lockAutoFormat = NO;
    }
}


#pragma mark - IBActions

- (void)saveScript
{
    self.detailItem.text = self.textView.text;
    [self.detailItem save];
}


- (IBAction)addShred
{
    if(self.detailItem == nil) return;
    
    std::string code = [self.textView.text UTF8String];
    std::string name = [self.detailItem.title UTF8String];
    std::string filepath;
    if(self.detailItem.path && [self.detailItem.path length])
        filepath = [self.detailItem.path UTF8String];
    vector<string> args;
    t_CKUINT shred_id;
    std::string output;
    
    t_OTF_RESULT otf_result = [mAChucKController chuckController].ma->run_code(code, name, args, filepath,
                                                                               self.detailItem.docid,
                                                                               shred_id, output);
    
    if( otf_result == OTF_SUCCESS )
    {
//        if([self.windowController currentViewController] == self)
//            [[text_view textView] animateAdd];
        self.textView.errorLine = -1;
        self.textView.errorMessage = nil;
        [self.textView animateAdd];
    }
    else if( otf_result == OTF_VM_TIMEOUT )
    {
//        miniAudicleController * mac = [NSDocumentController sharedDocumentController];
//        [mac setLockdown:YES];
    }
    else if( otf_result == OTF_COMPILE_ERROR )
    {
        int error_line;
        std::string result;
        if( [mAChucKController chuckController].ma->get_last_result( self.detailItem.docid, NULL, &result, &error_line ) )
        {
            self.textView.errorLine = error_line;
            self.textView.errorMessage = [NSString stringWithUTF8String:result.c_str()];
        }
        
//        if([self.windowController currentViewController] == self)
//            [[text_view textView] animateError];
        [self.textView animateError];
    }
    else
    {
//        if([self.windowController currentViewController] == self)
//            [[text_view textView] animateError];
//
//        [status_text setStringValue:[NSString stringWithUTF8String:result.c_str()]];
        [self.textView animateError];
    }
}


- (IBAction)replaceShred
{
    if(self.detailItem == nil) return;
    
    std::string code = [self.textView.text UTF8String];
    std::string name = [self.detailItem.title UTF8String];
    std::string filepath;
    if(self.detailItem.path && [self.detailItem.path length])
        filepath = [self.detailItem.path UTF8String];
    vector<string> args;
    t_CKUINT shred_id;
    std::string output;
    
    t_OTF_RESULT otf_result = [mAChucKController chuckController].ma->replace_code(code, name, args, filepath,
                                                                                   self.detailItem.docid,
                                                                                   shred_id, output);
    if( otf_result == OTF_SUCCESS )
    {
//        if([self.windowController currentViewController] == self)
//            [[text_view textView] animateAdd];
        self.textView.errorLine = -1;
        self.textView.errorMessage = nil;
        [self.textView animateReplace];
    }
    else if( otf_result == OTF_VM_TIMEOUT )
    {
//        miniAudicleController * mac = [NSDocumentController sharedDocumentController];
//        [mac setLockdown:YES];
    }
    else if( otf_result == OTF_COMPILE_ERROR )
    {
        int error_line;
        std::string result;
        if( [mAChucKController chuckController].ma->get_last_result( self.detailItem.docid, NULL, &result, &error_line ) )
        {
            self.textView.errorLine = error_line;
            self.textView.errorMessage = [NSString stringWithUTF8String:result.c_str()];
        }
        
        [self.textView animateError];
//        if([self.windowController currentViewController] == self)
//            [[text_view textView] animateError];
    }
    else
    {
//        if([self.windowController currentViewController] == self)
//            [[text_view textView] animateError];
//
//        [status_text setStringValue:[NSString stringWithUTF8String:result.c_str()]];
        [self.textView animateError];
    }
}


- (IBAction)removeShred
{
    if(self.detailItem == nil) return;
    
    t_CKUINT shred_id;
    std::string output;
    
    t_OTF_RESULT result = [mAChucKController chuckController].ma->remove_code(self.detailItem.docid,
                                                                              shred_id, output);
    
    if(result == OTF_SUCCESS)
    {
        [self.textView animateRemove];
    }
    else if(result == OTF_VM_TIMEOUT)
    {
    }
    else
    {
        [self.textView animateError];
    }
}


- (IBAction)editTitle:(id)sender
{
    if(self.popover == nil)
    {
        self.popover = [[UIPopoverController alloc] initWithContentViewController:self.titleEditor];
    }
    
    self.titleEditor.editedTitle = self.detailItem.title;
    self.titleEditor.delegate = self;
    self.popover.delegate = self;
    
    [self.popover presentPopoverFromBarButtonItem:self.titleButton
                         permittedArrowDirections:UIPopoverArrowDirectionUp
                                         animated:YES];
}


- (void)titleEditorDidConfirm:(mATitleEditorController *)titleEditor
{
    [self.popover dismissPopoverAnimated:YES];
    
    [self saveScript];
    
    //self.detailItem.title = self.titleEditor.editedTitle;
    [[mADocumentManager manager] renameScript:self.detailItem to:self.titleEditor.editedTitle];
    
    [self configureView];
    
    [self.masterViewController scriptDetailChanged];
}


- (void)titleEditorDidCancel:(mATitleEditorController *)titleEditor
{
    [self.popover dismissPopoverAnimated:YES];
}


#pragma mark - NSTextStorageDelegate

- (void)showCompletions:(NSArray *)completions forTextRange:(NSRange)range
{
    _textCompletionView.completions = completions;
    _textCompletionView.textAttributes = [self defaultTextAttributes];
    [_textCompletionView sizeToFit];
    
    CGRect textRect = [self.textView firstRectForRange:[self.textView textRangeFromRange:range]];
    CGRect frame = _textCompletionView.frame;
    frame.origin.x = textRect.origin.x;
    frame.origin.y = textRect.origin.y+textRect.size.height+4;
    _textCompletionView.frame = frame;
    
    if(_textCompletionView.superview == nil)
    {
        _textCompletionView.alpha = 0;
        [self.textView addSubview:_textCompletionView];
        
        [UIView animateWithDuration:1-G_RATIO
                            animations:^{
                                _textCompletionView.alpha = 1;
                            }];
    }
}

- (void)hideCompletions
{
    [UIView animateWithDuration:1-G_RATIO
                     animations:^{
                         _textCompletionView.alpha = 0;
                     } completion:^(BOOL finished) {
                         [_textCompletionView removeFromSuperview];
                     }];
}

- (int)indentationForTextPosition:(int)position
                     bracketLevel:(int)bracketLevel
                       parenLevel:(int)parenLevel
{
    NSString *text = self.textView.text;
    
    // determine whitespace for this line by scanning previous line
    
    // backward search
    // skip first newline (newline immediately preceding this line)
    
    int newline1Index = [text indexOfPreviousNewline:position];
    
    if(newline1Index == -1 || newline1Index == 0) return 0;
    
    // find next newline; count whitespace after it
    int newline2Index = -1;
    signed int braceCount = 0;
    signed int parenCount = parenLevel;
    signed int bracketCount = bracketLevel;
    int innerMostOpenBracketOrParen = -1;
    for(int i = newline1Index-1; i >= 0; i--)
    {
        unichar c = [text characterAtIndex:i];
        if(c == '\n' || c == '\r')
        {
            newline2Index = i;
            break;
        }
        if(c == '{') braceCount++;
        if(c == '}') braceCount--;
        if(c == '(') parenCount++;
        if(c == ')') parenCount--;
        if(c == '[') bracketCount++;
        if(c == ']') bracketCount--;
        
        // hanging open paren indent
        // indent to this level instead of regular indent
        if(parenCount > 0 && innerMostOpenBracketOrParen == -1) innerMostOpenBracketOrParen = i;
        if(bracketCount > 0 && innerMostOpenBracketOrParen == -1) innerMostOpenBracketOrParen = i;
    }
    
    if(innerMostOpenBracketOrParen != -1)
        return ::max(0, innerMostOpenBracketOrParen - newline2Index);
    if(parenCount < 0 || bracketCount < 0)
    {
        // close paren - adjust indent based on previous line
        if(newline2Index > 0)
            return [self indentationForTextPosition:newline2Index+1 bracketLevel:bracketCount parenLevel:parenCount];
        else
            return 0;
    }
    
    int addSpace = (braceCount>0 ? braceCount : 0) * 4;
    
    if(newline2Index == -1) return addSpace;
    
    int previousLineSpace = 0;
    NSCharacterSet *set = [NSCharacterSet whitespaceCharacterSet];
    for(int i = newline2Index+1; [set characterIsMember:[text characterAtIndex:i]]; i++)
    {
        unichar c = [text characterAtIndex:i];
        if(c == ' ') previousLineSpace++;
        else if(c == '\t') previousLineSpace += 4;
    }
    
    return ::max(0, previousLineSpace + addSpace);
}

- (void)textStorage:(NSTextStorage *)textStorage
 willProcessEditing:(NSTextStorageEditActions)editedMask
              range:(NSRange)editedRange
     changeInLength:(NSInteger)delta
{
    if(_lockAutoFormat)
        return;
    
    // scan for autocomplete
    BOOL hasCompletions = NO;
    if(editedRange.length == 1 && delta > 0)
    {
        mAAutocomplete *autocomplete = mAAutocomplete::autocomplete();
        
        __block int wordPos = 0;
        __block BOOL hasWord = NO;
        [[textStorage string] enumerateCharacters:^BOOL(int pos, unichar c) {
            if(autocomplete->isIdentifierChar(c))
                return YES;
            
            if(pos != editedRange.location &&
               (c != ':' && c != '.'))
            {
                wordPos = pos+1;
                hasWord = YES;
            }
            
            return NO;
        } fromPosition:editedRange.location reverse:YES];
        
        if(editedRange.location-wordPos+1 > 0)
        {
            vector<const string *> completions;
            NSString *word = [[textStorage string] substringWithRange:NSMakeRange(wordPos, editedRange.location-wordPos+1)];
            autocomplete->getCompletions([word stlString], completions);
            if(completions.size())
            {
//                for(int i = 0; i < completions.size(); i++)
//                    fprintf(stdout, "%s ", completions[i]->c_str());
//                fprintf(stdout, "\n");
//                fflush(stdout);
                NSMutableArray *_completions = [NSMutableArray new];
                for(int i = 0; i < completions.size(); i++)
                    [_completions addObject:[NSString stringWithSTLString:*completions[i]]];
                hasCompletions = YES;
                [self showCompletions:_completions forTextRange:NSMakeRange(wordPos, editedRange.location-wordPos+1)];
            }
        }
    }
    if(!hasCompletions)
        [self hideCompletions];
    
    // scan for newline or close brace
    // add/remove indentation as needed
    int charDelta = 0;
    for(int i = 0; i < editedRange.length && editedRange.location + i < [textStorage length]; i++)
    {
        int index = editedRange.location + i;
        unichar c = [[textStorage string] characterAtIndex:index];
        if(c == '\n' || c == '\r')
        {
            int nSpaces = [self indentationForTextPosition:index+1 bracketLevel:0 parenLevel:0];
            NSLog(@"%d spaces", nSpaces);
            if(nSpaces != 0)
            {
                charDelta += nSpaces;
                NSString *spaces = [@"" stringByPaddingToLength:nSpaces
                                                     withString:@" "
                                                startingAtIndex:0];
                [textStorage replaceCharactersInRange:NSMakeRange(index+1, 0) withString:spaces];
                i += nSpaces;
                editedRange.length += nSpaces;
            }
        }
        if(c == '}')
        {
            // remove spaces
            int nSpaces = [self indentationForTextPosition:index+1 bracketLevel:0 parenLevel:0];
            nSpaces = ::max(0, nSpaces-4);
            int newlineIndexPlus1 = [[textStorage string] indexOfPreviousNewline:index]+1;
            
            charDelta += nSpaces-(index-newlineIndexPlus1);
            NSString *spaces = [@"" stringByPaddingToLength:nSpaces
                                                 withString:@" "
                                            startingAtIndex:0];
            [textStorage replaceCharactersInRange:NSMakeRange(newlineIndexPlus1, index-newlineIndexPlus1) withString:spaces];
            editedRange.location += nSpaces-(index-newlineIndexPlus1);
        }
    }
    
    NSRange selectedRange = self.textView.selectedRange;
    if(charDelta != 0)
    {
        NSLog(@"charDelta: %d", charDelta);
        if(selectedRange.length == 0)
            self.textView.selectedRange = NSMakeRange(selectedRange.location+charDelta, 0);
        else
            self.textView.selectedRange = NSMakeRange(selectedRange.location, selectedRange.length+charDelta);
    }
}

- (void)textStorage:(NSTextStorage *)textStorage
  didProcessEditing:(NSTextStorageEditActions)editedMask
              range:(NSRange)editedRange
     changeInLength:(NSInteger)delta
{
    NSUInteger start_index, line_end_index, contents_end_index;
    [[textStorage string] getLineStart:&start_index
                                   end:&line_end_index
                           contentsEnd:&contents_end_index
                              forRange:editedRange];
    
    [[mASyntaxHighlighting sharedHighlighter] colorString:textStorage
                                                    range:NSMakeRange( start_index, contents_end_index - start_index )
                                                  colorer:nil];
}

#pragma mark - mAKeyboardAccessoryDelegate

- (void)keyPressed:(NSString *)chars
{
    [self.textView insertText:chars];
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if([text isEqualToString:@". "] && range.location != [textView selectedRange].location)
        return NO;
    
    return YES;
}


@end



@implementation NSString (CharacterEnumeration)

- (void)enumerateCharacters:(BOOL (^)(int pos, unichar c))block
               fromPosition:(NSInteger)index
                    reverse:(BOOL)reverse
{
    for(int i = index; reverse? (i >= 0) : (i < [self length]); reverse? i-- : i++)
    {
        if(!block(i, [self characterAtIndex:i])) break;
    }
}

- (void)enumerateCharacters:(BOOL (^)(int pos, unichar c))block
{
    [self enumerateCharacters:block fromPosition:0 reverse:NO];
}

@end



@implementation UITextView (Ranges)

- (UITextRange *)textRangeFromRange:(NSRange)range
{
    UITextPosition *docStart = self.beginningOfDocument;
    
    UITextPosition *start = [self positionFromPosition:docStart offset:range.location];
    UITextPosition *end = [self positionFromPosition:start offset:range.length];
    
    return [self textRangeFromPosition:start toPosition:end];
}

@end




