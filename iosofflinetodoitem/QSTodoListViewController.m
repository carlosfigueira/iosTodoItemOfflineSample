// ----------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ----------------------------------------------------------------------------
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <WindowsAzureMobileServices/WindowsAzureMobileServices.h>
#import "QSTodoListViewController.h"
#import "QSTodoService.h"
#import "QSTodoItemViewController.h"
#import "QSUIAlertViewWithBlock.h"

#pragma mark * Private Interface


@interface QSTodoListViewController () <UIAlertViewDelegate> {
    MSSyncItemBlock _block;
}

// Private properties
@property (strong, nonatomic)   QSTodoService   *todoService;
@property (nonatomic)           NSInteger       editedItemIndex;
@property (strong, nonatomic)   NSMutableDictionary *editedItem;

@end


#pragma mark * Implementation


@implementation QSTodoListViewController


#pragma mark * UIView methods


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Create the todoService - this creates the Mobile Service client inside the wrapped service
    self.todoService = [QSTodoService defaultServiceWithDelegate:self];
    
    // Set the busy method
    UIActivityIndicatorView *indicator = self.activityIndicator;
    self.todoService.busyUpdate = ^(BOOL busy)
    {
        if (busy)
        {
            [indicator startAnimating];
        }
        else
        {
            [indicator stopAnimating];
        }
    };
    
    [[self navigationItem] setTitle:@"Azure Mobile Services"];

    [self.refreshControl addTarget:self
                            action:@selector(onRefresh:)
                  forControlEvents:UIControlEventValueChanged];
    
    // load the data
    [self refresh];
}

- (void) refresh
{
    // only activate the refresh control if the feature is available
    [self.refreshControl beginRefreshing];

    [self.todoService refreshDataOnSuccess:^
    {
        [self.refreshControl endRefreshing];
        [self.tableView reloadData];
    }];
}

#pragma mark * Storyboard methods

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([[segue identifier] isEqualToString:@"detailSegue"]) {
        QSTodoItemViewController *ivc = (QSTodoItemViewController *)[segue destinationViewController];
        ivc.item = self.editedItem;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    if (self.editedItem && self.editedItemIndex >= 0) {
        // Returning from the details view controller
        NSDictionary *item = [self.todoService.items objectAtIndex:self.editedItemIndex];
        
        BOOL changed = ![item isEqualToDictionary:self.editedItem];
        if (changed) {
            [self.tableView setUserInteractionEnabled:NO];
            
            // Change the appearance to look greyed out until we remove the item
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.editedItemIndex inSection:0];
            
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            cell.textLabel.textColor = [UIColor grayColor];

            // Ask the todoService to update the item, and remove the row if it's been completed
            [self.todoService updateItem:self.editedItem atIndex:self.editedItemIndex completion:^(NSUInteger index) {
                if ([[self.editedItem objectForKey:@"complete"] boolValue]) {
                    // Remove the row from the UITableView
                    [self.tableView deleteRowsAtIndexPaths:@[ indexPath ]
                                          withRowAnimation:UITableViewRowAnimationTop];
                } else {
                    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                                          withRowAnimation:UITableViewRowAnimationAutomatic];
                }
                
                [self.tableView setUserInteractionEnabled:YES];
                
                self.editedItem = nil;
                self.editedItemIndex = -1;
            }];
        } else {
            self.editedItem = nil;
            self.editedItemIndex = -1;
        }
    }
}

#pragma mark * UITableView methods

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.editedItemIndex = [indexPath row];
    self.editedItem = [[self.todoService.items objectAtIndex:[indexPath row]] mutableCopy];
    
    [self performSegueWithIdentifier:@"detailSegue" sender:self];
}

-(UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Editing will be done in the detail view
    return UITableViewCellEditingStyleNone;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    NSDictionary *item = [self.todoService.items objectAtIndex:indexPath.row];
    cell.textLabel.text = [item objectForKey:@"text"];
    cell.textLabel.textColor = [UIColor blackColor];
    
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Always a single section
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of items in the todoService items array
    return [self.todoService.items count];
}


#pragma mark * UITextFieldDelegate methods


-(BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}


#pragma mark * UI Actions


- (IBAction)onAdd:(id)sender
{
    if (self.itemText.text.length == 0)
    {
        return;
    }
    
    NSDictionary *item = @{ @"text" : self.itemText.text, @"complete" : @NO };
    UITableView *view = self.tableView;
    [self.todoService addItem:item completion:^(NSUInteger index)
    {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        [view insertRowsAtIndexPaths:@[ indexPath ]
                    withRowAnimation:UITableViewRowAnimationTop];
    }];
    
    self.itemText.text = @"";
}


#pragma mark * iOS Specific Code


- (void)onRefresh:(id) sender
{
    [self refresh];
}

- (void)tableOperation:(MSTableOperation *)operation onComplete:(MSSyncItemBlock)completion
{
    [self doOperation:operation complete:completion];
}

- (void)doOperation:(MSTableOperation *)operation complete:(MSSyncItemBlock)completion
{
    [operation executeWithCompletion:^(NSDictionary *item, NSError *error) {
        if (error.code == MSErrorPreconditionFailed) {
            QSUIAlertViewWithBlock *alert = [[QSUIAlertViewWithBlock alloc] initWithCallback:^(NSInteger buttonIndex) {
                if (buttonIndex == 1) { // Client
                    NSDictionary *serverItem = [error.userInfo objectForKey:MSErrorServerItemKey];
                    NSMutableDictionary *adjustedItem = [operation.item mutableCopy];
                    
                    [adjustedItem setValue:[serverItem objectForKey:MSSystemColumnVersion] forKey:MSSystemColumnVersion];
                    operation.item = adjustedItem;
                    
                    [self doOperation:operation complete:completion];
                    return;
                    
                } else if (buttonIndex == 2) { // Server
                    NSDictionary *serverItem = [error.userInfo objectForKey:MSErrorServerItemKey];
                    completion(serverItem, nil);
                } else { // Cancel
                    [operation cancelPush];
                    completion(nil, error);
                }
            }];
            
            [alert showAlertWithTitle:@"Server Conflict"
                              message:@"How do you want to resolve the conflict?"
                    cancelButtonTitle:@"Cancel"
                    otherButtonTitles:[NSArray arrayWithObjects:@"Use Client", @"Use Server", nil]];
        } else {
            completion(item, error);
        }
    }];
}

@end
