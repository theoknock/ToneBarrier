//
//  ViewController.m
//  ToneBarrierAppClip
//
//  Created by Xcode Developer on 8/1/20.
//  Copyright © 2020 The Life of a Demoniac. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (IBAction)playTones:(UIButton *)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![[[ToneGenerator sharedGenerator] audioEngine] isRunning]) {
            [[ToneGenerator sharedGenerator] play];
        } else if ([[[ToneGenerator sharedGenerator] audioEngine] isRunning]) {
            [[ToneGenerator sharedGenerator] stop];
        }
    });
}



@end
