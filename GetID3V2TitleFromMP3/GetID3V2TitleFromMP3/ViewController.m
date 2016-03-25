//
//  ViewController.m
//  GetID3V2TitleFromMP3
//
//  Created by 杨超杰 on 16/3/24.
//  Copyright © 2016年 ZHOU. All rights reserved.
//

#import "ViewController.h"
#import <Masonry/Masonry.h>

@interface ViewController ()

@property (nonatomic, strong)UILabel* showTitleLabel;
@property (nonatomic, strong)UIButton* analysisButton;

@property (nonatomic, strong)dispatch_queue_t analysisQueue;

@property (nonatomic, strong)NSArray<NSString*>* musicFileNames;


@end

@implementation ViewController

#pragma mark - 控制器生命周期方法

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.musicFileNames = @[@"music1",@"music2"];
    
    self.view.backgroundColor = [UIColor grayColor];
    
    self.showTitleLabel.font = [UIFont systemFontOfSize:30.0f];
    self.showTitleLabel.text = @"未读取数据";
    self.showTitleLabel.textAlignment = NSTextAlignmentCenter;

    [self.analysisButton setTitle:@"开始解析" forState:UIControlStateNormal];
    [self.analysisButton addTarget:self action:@selector(startAnalysis) forControlEvents:UIControlEventTouchUpInside];
    [self.analysisButton setBackgroundColor:[UIColor orangeColor]];
    
    [self.view addSubview:self.showTitleLabel];
    [self.view addSubview:self.analysisButton];
    
    //添加约束
    __weak ViewController* weakSelf = self;
    
    [self.showTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(weakSelf.view);
    }];
    
    [self.analysisButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.equalTo(weakSelf.view).multipliedBy(0.33f);
        make.height.equalTo(weakSelf.analysisButton.mas_width).multipliedBy(0.33f);
        make.centerX.equalTo(weakSelf.view);
        make.bottom.equalTo(weakSelf.view).offset(-50.0f);
    }];
}

#pragma mark - UI触发的方法

-(void)startAnalysis
{
    self.showTitleLabel.textColor = [UIColor whiteColor];
    self.showTitleLabel.text = @"解析中";
    __weak ViewController* weakSelf = self;
    
    dispatch_async(weakSelf.analysisQueue, ^{
        
        NSInteger index = arc4random() % [[weakSelf musicFileNames]count];
        
        NSString* musicName = [[weakSelf musicFileNames]objectAtIndex:index];
        
        NSData* MP3Data = [[NSData alloc]initWithContentsOfFile:[[NSBundle mainBundle]pathForResource:musicName ofType:@"mp3"]];
        
        if (!MP3Data)
        {
            NSLog(@"读取数据失败");
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.showTitleLabel setTextColor:[UIColor redColor]];
                [weakSelf.showTitleLabel setText:@"读取数据失败"];
            });
            return;
        }
        
        NSData* ID3V2Data = [weakSelf searchID3V2DataOnMP3Data:MP3Data];
        
        if (!ID3V2Data)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.showTitleLabel setTextColor:[UIColor redColor]];
                [weakSelf.showTitleLabel setText:@"没有v2.3版本的ID3头部"];
            });
            return;
        }
        
        NSData* ID3V2TitleData = [weakSelf searchID3V2TitleDataOnID3V2Data:ID3V2Data];
        
        if (!ID3V2TitleData)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.showTitleLabel setTextColor:[UIColor redColor]];
                [weakSelf.showTitleLabel setText:@"没有标题标签"];
            });
            return;
        }
        
        NSString* ID3V2Title = [weakSelf ID3V2TitleFromData:ID3V2TitleData];
        
        if (!ID3V2Title)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.showTitleLabel setTextColor:[UIColor redColor]];
                [weakSelf.showTitleLabel setText:@"标题解析失败"];
            });
            
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.showTitleLabel setTextColor:[UIColor greenColor]];
            [weakSelf.showTitleLabel setText:ID3V2Title];
        });
    });
}

#pragma mark - ID3V2解析核心方法

//在ID3V2数据中找出TIT2标签的内容
-(NSData* _Nullable)searchID3V2TitleDataOnID3V2Data:(NSData*)ID3V2Data
{
    NSData* TIT2StringData = [@"TIT2" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSRange TIT2StringRange = [ID3V2Data rangeOfData:TIT2StringData options:NSDataSearchBackwards range:NSMakeRange(0, ID3V2Data.length)];
    
    if (TIT2StringRange.location == NSNotFound)
    {
        NSLog(@"此MP3文件的ID3V2头部没有保存标题信息");
        
        return nil;
    }
    
    //"TIT2"标识符开始处向后移动四位到八位表示该标签的内容长度信息
    NSData* TIT2LabelLenghtData = [ID3V2Data subdataWithRange:NSMakeRange(TIT2StringRange.location + 4, 4)];
    
    NSUInteger TIT2LabelLenght = getTIT2lenght((char*)TIT2LabelLenghtData.bytes);
    
    return [ID3V2Data subdataWithRange:NSMakeRange(TIT2StringRange.location + 10, TIT2LabelLenght)];
}

//获取一个MP3文件的ID3V2头信息
-(NSData* _Nullable)searchID3V2DataOnMP3Data:(NSData*)MP3Data
{
    NSData* ID3Stringdata = [@"ID3" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSRange ID3StringRange = [MP3Data rangeOfData:ID3Stringdata options:NSDataSearchAnchored range:NSMakeRange(0, MP3Data.length)];
    
    if (ID3StringRange.location == NSNotFound)
    {
        NSLog(@"不存在ID3V2信息");
        
        return nil;
    }
    
    //获取版本号
    char ver;
    strcpy(&ver,(char*)(MP3Data.bytes + ID3StringRange.location + 3));
    
    char known_ver = 0x03;
    
    //判断版本
    if (ver != known_ver)
    {
        NSLog(@"不是2.3版本ID3头部，无法处理");
        return nil;
    }
    
    //"ID3"标识符开始位后移六个字节至第十个字节是表示ID3V2头的长度信息
    NSData* ID3V2DatalenghtData = [MP3Data subdataWithRange:NSMakeRange(ID3StringRange.location + 6, 4)];
    NSUInteger ID3V2Datalenght = gettotalLenght((char*)ID3V2DatalenghtData.bytes);
    
    
    return [MP3Data subdataWithRange:NSMakeRange(ID3StringRange.location, ID3V2Datalenght)];
}

//将二进制数据转换为字符串
-(NSString* _Nullable)ID3V2TitleFromData:(NSData*)TitleData
{
    //第一个字节是SOH控制符，需要去掉
    NSData* titleStringData = [TitleData subdataWithRange:NSMakeRange(1, TitleData.length - 1)];
    
    NSString* title = [[NSString alloc]initWithData:titleStringData encoding:NSUnicodeStringEncoding];
    
    return title;
}



#pragma mark - 惰性初始化

-(UILabel*)showTitleLabel
{
    if (!_showTitleLabel)
    {
        _showTitleLabel = [[UILabel alloc]init];
    }
    
    return _showTitleLabel;
}

-(UIButton*)analysisButton
{
    if (!_analysisButton)
    {
        _analysisButton = [[UIButton alloc]init];
    }
    
    return _analysisButton;
}

-(dispatch_queue_t)analysisQueue
{
    if (!_analysisQueue)
    {
        _analysisQueue = dispatch_queue_create("MIANSHI.GetID3V2TitleFromMP3.analysisQueue", NULL);
    }
    
    return _analysisQueue;
}

#pragma mark - 计算用到的C函数

//获取MP3中整个ID3V2头部信息的长度
int gettotalLenght(char* a)
{
    return (a[0]&0x7F)*0x200000+(a[1]&0x7F)*0x400+(a[2]&0x7F)*0x80+(a[3]&0x7F);
}

//获取ID3V2头部信息中某个标签的内容信息长度
long getTIT2lenght(char* a)
{
    return a[0]*0x100000000+a[1]*0x10000+a[2]*0x100+a[3];
    
}

@end
