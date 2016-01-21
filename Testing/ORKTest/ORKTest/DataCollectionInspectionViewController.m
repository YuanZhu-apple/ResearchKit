/*
 Copyright (c) 2016, Apple Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1.  Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2.  Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.
 
 3.  Neither the name of the copyright holder(s) nor the names of any contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission. No license is granted to the trademarks of
 the copyright holders even if such marks are included in this software.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#import "DataCollectionInspectionViewController.h"
#import <ResearchKit/ResearchKit.h>
#import "DataCollectionTester.h"


@implementation DataCollectionInspectionViewController {
    NSMutableArray<NSMutableArray<ORKUploadableItem *> *> *_dataSections;
    ORKUploadableDataStore *_dataStore;
    NSDateFormatter *_dateFormatter;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Collected Data Inspector";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(dismissAction)];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                                           target:self
                                                                                           action:@selector(resetAction)];
    if (_dateFormatter == nil) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateStyle = NSDateFormatterShortStyle;
        _dateFormatter.timeStyle = NSDateFormatterMediumStyle;
    }
    
    [self reloadDataItems];
}

- (void)reloadDataItems {
    _dataStore = [DataCollectionTester dataStore];
    _dataSections = [NSMutableArray new];
    __block NSMutableArray<ORKUploadableItem *> *dataSection = [NSMutableArray new];
    [_dataStore enumerateManagedItems:^(ORKUploadableItem * _Nonnull dataItem, BOOL * _Nonnull stop) {
        if (dataSection.count > 0) {
            if ([dataItem.creationDate timeIntervalSinceDate:dataSection.lastObject.creationDate] > 10) {
                [_dataSections addObject:dataSection];
                dataSection = [NSMutableArray new];
            }
            [dataSection addObject:dataItem];
        } else {
            [dataSection addObject:dataItem];
        }
    }                       exclusion:ORKDataStoreExclusionOptionNone
                              sorting:ORKDataStoreSortingOptionByCreationDate
                            ascending:YES error:nil];
    
    [_dataSections addObject:dataSection];
    
    [self.tableView reloadData];
}

- (void)dismissAction {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetAction {
    [DataCollectionTester resetTestPath];
    [self reloadDataItems];
}

#pragma mark - tableView delegate/datasource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _dataSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _dataSections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dataItem"];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"dataItem"];
    }
    
    ORKUploadableDataItem *item = (ORKUploadableDataItem *)_dataSections[indexPath.section][indexPath.row];
    NSArray<NSDictionary *> *samples = [NSJSONSerialization JSONObjectWithData:item.data options:0 error:nil];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ = %@", item.metadata[@"type"], @(samples.count)];
    cell.backgroundColor = [cell.textLabel.text hasPrefix:@"heart"] ? [[UIColor redColor] colorWithAlphaComponent:0.1] : [cell.textLabel.text hasPrefix:@"log"] ? [[UIColor lightGrayColor] colorWithAlphaComponent:0.1] : [[UIColor greenColor] colorWithAlphaComponent:0.1];
    
    if ([cell.textLabel.text hasPrefix:@"log"] == NO) {
        cell.detailTextLabel.text =  [NSString stringWithFormat:@"[%@, %@]", [samples.firstObject[@"startDate"] substringWithRange:NSMakeRange(11, 8)], [samples.lastObject[@"startDate"] substringWithRange:NSMakeRange(11, 8)]];
    } else {
        cell.detailTextLabel.text = [[NSString stringWithFormat:@"%@", [samples valueForKeyPath:@"anchor"]] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    }
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    ORKUploadableDataItem *item = (ORKUploadableDataItem *)_dataSections[section][0];
    return [_dateFormatter stringFromDate:item.creationDate];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    __block ORKUploadableDataItem *item = (ORKUploadableDataItem *)_dataSections[indexPath.section][indexPath.row];
    __block UIViewController *textViewController = [UIViewController new];
    [self.navigationController pushViewController:textViewController animated:YES];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(0,64, textViewController.view.bounds.size.width, textViewController.view.bounds.size.height - 64) ];
        textView.autoresizingMask = UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
        [textViewController.view addSubview:textView];
        textView.editable = NO;
        textView.text = [[NSJSONSerialization JSONObjectWithData:item.data options:0 error:nil] description];
    });
}

@end
