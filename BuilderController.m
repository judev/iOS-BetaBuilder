//
//  BuilderController.m
//  BetaBuilder
//
//  Created by Hunter Hillegas on 8/7/10.
//  Copyright 2010 Hunter Hillegas. All rights reserved.
//

/* 
 iOS BetaBuilder - a tool for simpler iOS betas
 Version 1.0, August 2010
 
 Condition of use and distribution:
 
 This software is provided 'as-is', without any express or implied
 warranty.  In no event will the authors be held liable for any damages
 arising from the use of this software.
 
 Permission is granted to anyone to use this software for any purpose,
 including commercial applications, and to alter it and redistribute it
 freely, subject to the following restrictions:
 
 1. The origin of this software must not be misrepresented; you must not
 claim that you wrote the original software. If you use this software
 in a product, an acknowledgment in the product documentation would be
 appreciated but is not required.
 2. Altered source versions must be plainly marked as such, and must not be
 misrepresented as being the original software.
 3. This notice may not be removed or altered from any source distribution.
 */

#import "BuilderController.h"
#import "ZipArchive.h"

@implementation BuilderController

@synthesize bundleIdentifierField;
@synthesize bundleVersionField;
@synthesize bundleNameField;
@synthesize webserverDirectoryField;
@synthesize archiveIPAFilenameField;
@synthesize generateFilesButton;
@synthesize mobileProvisionFilePath;

- (IBAction)specifyIPAFile:(id)sender {
	NSOpenPanel *openDlg = [NSOpenPanel openPanel];
	[openDlg setCanChooseFiles:YES];
	[openDlg setCanChooseDirectories:NO];
	[openDlg setAllowsMultipleSelection:NO];

	if ([openDlg runModalForDirectory:nil file:nil] == NSOKButton) {
		NSArray *files = [openDlg filenames];

		for (int i = 0; i < [files count]; i++ ) {
			[self setupFromIPAFile:[files objectAtIndex:i]];
		}
	}
}

- (void)setupFromIPAFile:(NSString *)ipaFilename {
	[archiveIPAFilenameField setStringValue:ipaFilename];
	
	//Attempt to pull values
	NSError *fileCopyError;
	NSError *fileDeleteError;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSURL *ipaSourceURL = [NSURL fileURLWithPath:[archiveIPAFilenameField stringValue]];
	NSURL *ipaDestinationURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), [[archiveIPAFilenameField stringValue] lastPathComponent]]];
	[fileManager removeItemAtURL:ipaDestinationURL error:&fileDeleteError];
	BOOL copiedIPAFile = [fileManager copyItemAtURL:ipaSourceURL toURL:ipaDestinationURL error:&fileCopyError];
	if (!copiedIPAFile) {
		NSLog(@"Error Copying IPA File: %@", fileCopyError);
	} else {
		//Remove Existing Trash in Temp Directory
		[fileManager removeItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"extracted_app"] error:nil];
		
		ZipArchive *za = [[ZipArchive alloc] init];
		if ([za UnzipOpenFile:[ipaDestinationURL path]]) {
			BOOL ret = [za UnzipFileTo:[NSTemporaryDirectory() stringByAppendingPathComponent:@"extracted_app"] overWrite:YES];
			if (NO == ret){} [za UnzipCloseFile];
		}
		[za release];
		
		//read the Info.plist file
		NSString *appDirectoryPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"extracted_app"] stringByAppendingPathComponent:@"Payload"];
		NSArray *payloadContents = [fileManager contentsOfDirectoryAtPath:appDirectoryPath error:nil];
		if ([payloadContents count] > 0) {
			NSString *plistPath = [[payloadContents objectAtIndex:0] stringByAppendingPathComponent:@"Info.plist"];
			NSDictionary *bundlePlistFile = [NSDictionary dictionaryWithContentsOfFile:[appDirectoryPath stringByAppendingPathComponent:plistPath]];
			
			if (bundlePlistFile) {
				[bundleVersionField setStringValue:[bundlePlistFile valueForKey:@"CFBundleVersion"]];
				[bundleIdentifierField setStringValue:[bundlePlistFile valueForKey:@"CFBundleIdentifier"]];
				[bundleNameField setStringValue:[bundlePlistFile valueForKey:@"CFBundleDisplayName"]];
			}
			
			//set mobile provision file
			mobileProvisionFilePath = [appDirectoryPath stringByAppendingPathComponent:[[payloadContents objectAtIndex:0] stringByAppendingPathComponent:@"embedded.mobileprovision"]];
		}
	}
	
	[generateFilesButton setEnabled:YES];
}

- (IBAction)generateFiles:(id)sender {
	//create plist
	NSString *encodedIpaFilename = [[[archiveIPAFilenameField stringValue] lastPathComponent] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; //this isn't the most robust way to do this
	
	NSString *appName = [encodedIpaFilename stringByDeletingPathExtension];
	NSString *appExtension = [encodedIpaFilename pathExtension];
	NSString *betaZipFilename = [appName stringByAppendingPathExtension:@"zip"];
	NSString *betaIpaFilename = [[appName stringByAppendingString:@"_Beta"] stringByAppendingPathExtension:appExtension];
	NSString *betaProvisionFilename = [appName stringByAppendingString:@"_AdHoc.mobileprovision"];
	
	NSString *ipaURLString = [NSString stringWithFormat:@"%@/%@", [webserverDirectoryField stringValue], betaIpaFilename];
	NSDictionary *assetsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"software-package", @"kind", ipaURLString, @"url", nil];
	NSDictionary *metadataDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[bundleIdentifierField stringValue], @"bundle-identifier", [bundleVersionField stringValue], @"bundle-version", @"software", @"kind", [bundleNameField stringValue], @"title", nil];
	NSDictionary *innerManifestDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:assetsDictionary], @"assets", metadataDictionary, @"metadata", nil];
	NSDictionary *outerManifestDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:innerManifestDictionary], @"items", nil];
	NSLog(@"Manifest Created");
	
	//create html file
	NSString *templatePath = [[NSBundle mainBundle] pathForResource:@"index_template" ofType:@"html"];
	NSString *htmlTemplateString = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:nil];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_NAME]" withString:[bundleNameField stringValue]];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_ZIP_NAME]" withString:betaZipFilename];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_PLIST]" withString:[NSString stringWithFormat:@"%@/%@", [webserverDirectoryField stringValue], @"manifest.plist"]];
	
	//ask for save location	
	NSOpenPanel *directoryPanel = [NSOpenPanel openPanel];
	[directoryPanel setCanChooseFiles:NO];
	[directoryPanel setCanChooseDirectories:YES];
	[directoryPanel setAllowsMultipleSelection:NO];
	[directoryPanel setCanCreateDirectories:YES];
	[directoryPanel setPrompt:@"Choose Directory"];
	[directoryPanel setMessage:@"Choose the Directory for Beta Files - Probably Should Match Deployment Directory"];
	
	if ([directoryPanel runModalForDirectory:nil file:nil] == NSOKButton) {
		NSURL *saveDirectoryURL = [directoryPanel directoryURL];
		
		//Write Files
		[outerManifestDictionary writeToURL:[saveDirectoryURL URLByAppendingPathComponent:@"manifest.plist"] atomically:YES];
		[htmlTemplateString writeToURL:[saveDirectoryURL URLByAppendingPathComponent:@"index.html"] atomically:YES encoding:NSASCIIStringEncoding error:nil];
		
		//Copy IPA
		NSError *fileCopyError;
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSURL *ipaSourceURL = [NSURL fileURLWithPath:[archiveIPAFilenameField stringValue]];
		NSURL *ipaDestinationURL = [saveDirectoryURL URLByAppendingPathComponent:betaIpaFilename];
		BOOL copiedIPAFile = [fileManager copyItemAtURL:ipaSourceURL toURL:ipaDestinationURL error:&fileCopyError];
		if (!copiedIPAFile) {
			NSLog(@"Error Copying IPA File: %@", fileCopyError);
		}
		
		//Copy README
		NSString *readmeContents = [[NSBundle mainBundle] pathForResource:@"README" ofType:@""];
		[readmeContents writeToURL:[saveDirectoryURL URLByAppendingPathComponent:@"README.txt"] atomically:YES encoding:NSASCIIStringEncoding error:nil];
		
		//Create Archived Version for 3.0 Apps
		ZipArchive* zip = [[ZipArchive alloc] init];
		
		BOOL ret = [zip CreateZipFile2:[[saveDirectoryURL path] stringByAppendingPathComponent:betaZipFilename]];
		ret = [zip addFileToZip:[archiveIPAFilenameField stringValue] newname:betaIpaFilename];
		ret = [zip addFileToZip:mobileProvisionFilePath newname:betaProvisionFilename];
		if(![zip CloseZipFile2]) {
			NSLog(@"Error Creating 3.x Zip File");
		}
		[zip release];
		
		//Play Done Sound / Display Alert
		NSSound *systemSound = [NSSound soundNamed:@"Glass"];
		[systemSound play];
	}
}

@end
