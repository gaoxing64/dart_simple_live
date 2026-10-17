//! 抖音标准表情包表（214 项，2026-10-17 抓自网页端表情面板）。
//!
//! 数据来源：网页 roomStore.emojiList（React context 的 value.list），每项
//! display_name 是 [微笑] 这类文本码，url 为签名 CDN 地址（有效期至 2036-10）。
//! 普通聊天只下发文本码（rtfContent 为空），图片不在消息里，因此只能靠这张表
//! 把占位符替换成图片；未命中表的方括号文本保持原样。
//!
//! 口径对齐虎牙：只输出正文里真实出现的码；重复出现保留多个；large = false
//! （行内表情，高度跟随聊天字号）。

use std::collections::HashMap;

use once_cell::sync::Lazy;

use crate::models::LiveMessageEmoticon;

/// 文本码 -> 图片地址（顺序与网页端表情面板一致）。
const DOUYIN_EMOTICONS: &[(&str, &str)] = &[
    ("[微笑]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/54a0f69dc150401a85ba8c20c1a05db1?lk3s=343af0a2&x-expires=2107598400&x-signature=uhsy380U4csYfbfmYqKKAxI0dAg%3D&from=876277922"),
    ("[色]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/27a1d35dea9748ac8c14f6c2c9829965?lk3s=343af0a2&x-expires=2107598400&x-signature=VndqUhksp8SzYIxkbam4Y5j4dgE%3D&from=876277922"),
    ("[发呆]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/88ebe7b3f2e24729aa4de3ff33ae5731?lk3s=343af0a2&x-expires=2107598400&x-signature=jKfSOqNkU2qW4IYTkqkIMgH4S80%3D&from=876277922"),
    ("[酷拽]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/0fac43466165409a805b3b6e3547ccef?lk3s=343af0a2&x-expires=2107598400&x-signature=s3fhdDEjq09OgcyZECMfyoCdoGw%3D&from=876277922"),
    ("[抠鼻]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/accde8fa9fe04c5e8fa3f25d1ddb5584?lk3s=343af0a2&x-expires=2107598400&x-signature=D288IbC1Y0X59G2E2lIddUhmnVc%3D&from=876277922"),
    ("[流泪]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/2d8dc1e2bb8a417cab4130df2d10e478?lk3s=343af0a2&x-expires=2107598400&x-signature=y5DPeUCJ4LWXQelmgICKsib1rRg%3D&from=876277922"),
    ("[捂脸]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/357ac72b9b6449f7bd3005ff66678822?lk3s=343af0a2&x-expires=2107598400&x-signature=dQZCav7bHboLoXkzG8VyDwS%2BbQs%3D&from=876277922"),
    ("[发怒]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/156352b6879b4b5f96fd80434ff72c8e?lk3s=343af0a2&x-expires=2107598400&x-signature=u3EGiQntBAvB%2Bw5K1WVYBZhenlE%3D&from=876277922"),
    ("[呲牙]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/17bc9c4501784279b8e7d886832b0f28?lk3s=343af0a2&x-expires=2107598400&x-signature=%2BlfPBVnZcXmaM6EwWuKdd%2BpFvLk%3D&from=876277922"),
    ("[尬笑]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/96744c9a302345d1b14d7e0a9951c7b9?lk3s=343af0a2&x-expires=2107598400&x-signature=NTKSBLGRBPCnYVi5nhD7s7Pw%2FIs%3D&from=876277922"),
    ("[害羞]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d05cee2608fe4f998fef3f90de9466df?lk3s=343af0a2&x-expires=2107598400&x-signature=2O8lnjNHIhfrjtpgroBePAv0N2k%3D&from=876277922"),
    ("[调皮]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/a921fa28653043c1bbf162abe017c99a?lk3s=343af0a2&x-expires=2107598400&x-signature=zjaA07RxWIylNNiejUd5VMsFngw%3D&from=876277922"),
    ("[舔屏]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d99bd102d422484188b98e8889c0c330?lk3s=343af0a2&x-expires=2107598400&x-signature=cDVL%2FsINBlImdxGAlqGtbNGRBl8%3D&from=876277922"),
    ("[看]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/87c2ae45679c4cc4a35bd7182fd76935?lk3s=343af0a2&x-expires=2107598400&x-signature=mb8KGJBP5qVgB4B106J33j2aJFY%3D&from=876277922"),
    ("[爱心]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/427b632213784532a4076c3b0ab269fb?lk3s=343af0a2&x-expires=2107598400&x-signature=7PLanZNposAhmZEdnGeoUhojXsY%3D&from=876277922"),
    ("[比心]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/75b4e7e2405447959578f54d87811e35?lk3s=343af0a2&x-expires=2107598400&x-signature=UyCUmLH6fgmB5HUgi9j2PiBhmS8%3D&from=876277922"),
    ("[赞]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/1a09f79a0e7e433eb2bc143c9f026d65?lk3s=343af0a2&x-expires=2107598400&x-signature=IzX3nYDo8xkF6Qy96V%2F3jocbH34%3D&from=876277922"),
    ("[鼓掌]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/15d1258bec8e4c9ea9687f1134bd5f65?lk3s=343af0a2&x-expires=2107598400&x-signature=Ol4j3Fh0mpinzlwpeFJYePApiCo%3D&from=876277922"),
    ("[感谢]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/fabab8b14ec64f669283287a4b7041cb?lk3s=343af0a2&x-expires=2107598400&x-signature=kyJAxsEzvofQ2fb805MlpMrm6UI%3D&from=876277922"),
    ("[抱抱你]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/299f50b8f96640d5b349cc6cb4a76030?lk3s=343af0a2&x-expires=2107598400&x-signature=iz9Twj4WD%2BlJHpV%2F%2FWBBfZ7Je5U%3D&from=876277922"),
    ("[玫瑰]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/683fcd46faf148af99c90e36ccc4c013?lk3s=343af0a2&x-expires=2107598400&x-signature=ChbJum38UCTe4t8em6lo7jc1B7o%3D&from=876277922"),
    ("[尴尬流汗]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/160eca1320584e2e87122e7d7ba72a53?lk3s=343af0a2&x-expires=2107598400&x-signature=ap16VOY0vnXMW%2F1A66XwNYax0wk%3D&from=876277922"),
    ("[戳手手]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/4268c0b885ec4eae8e95dab8635ca215?lk3s=343af0a2&x-expires=2107598400&x-signature=7pfwyOlTJkvnjZLn3GDOzdaGblo%3D&from=876277922"),
    ("[星星眼]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/007064f99b694041a1890e52ff8c5768?lk3s=343af0a2&x-expires=2107598400&x-signature=FLhFsnCLOmlwfF4%2FISQCpAHZPWs%3D&from=876277922"),
    ("[杀马特]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ed5fb68598cf4741b3e7f2affd825650?lk3s=343af0a2&x-expires=2107598400&x-signature=U1jZc8BpPKfPmfcEz0%2FG23OzQKM%3D&from=876277922"),
    ("[黄脸干杯]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/a0a1e35991334532b142572d93f38ac5?lk3s=343af0a2&x-expires=2107598400&x-signature=w5mPTmq0nqnj2QWmqUwN%2BjD4ECg%3D&from=876277922"),
    ("[抱紧自己]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c0cf6b7d6a144b68b6045fd92bfe9fe2?lk3s=343af0a2&x-expires=2107598400&x-signature=qMfh58yEYQ4yFPjFS3jOheqPUFE%3D&from=876277922"),
    ("[拜拜]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/36cf73734e9c49d48b3e9a5bbe2affaf?lk3s=343af0a2&x-expires=2107598400&x-signature=53WxnP2sYNUh3r%2B8blStUv6UUrs%3D&from=876277922"),
    ("[热化了]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/2cffc18234074d20acb0c6334c76f04a?lk3s=343af0a2&x-expires=2107598400&x-signature=FD6a8CuXBDb2KnRZDXohkl6HpA4%3D&from=876277922"),
    ("[黄脸祈祷]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/3f67722d0c694372b7023deda01bd91c?lk3s=343af0a2&x-expires=2107598400&x-signature=WHgw0o54T3ZzEhCTBfM%2Bi0JV2T0%3D&from=876277922"),
    ("[懵]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/dbd68a1183b344648759f5971cbc6238?lk3s=343af0a2&x-expires=2107598400&x-signature=Z7p4nPnoCrbKrz70WkJvpsZ0FvQ%3D&from=876277922"),
    ("[举手]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/3c34da0d65db47c6933e6b66cc17e5aa?lk3s=343af0a2&x-expires=2107598400&x-signature=qTSvrOxHemQ5b5ux2ksUqWO1BLU%3D&from=876277922"),
    ("[加功德]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/49b00fcf022d4c36ba86bb19c7358ec6?lk3s=343af0a2&x-expires=2107598400&x-signature=JbJnNXCGCZuJyP8xEL%2F46yl6z%2FA%3D&from=876277922"),
    ("[摊手]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/6ffc70d8850b4e5eb6c7a5aa9e7b1782?lk3s=343af0a2&x-expires=2107598400&x-signature=Q632ZnEc2u0MmhHWoaUwQp5Ar6E%3D&from=876277922"),
    ("[无语流汗]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/67f5a31e2895499dbfff97ff81efb0f8?lk3s=343af0a2&x-expires=2107598400&x-signature=WtbL8dGQAqQGlxeDz34qVcJVvNQ%3D&from=876277922"),
    ("[续火花吧]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/1da1cd2598ba48a78cf07dc7eea09338?lk3s=343af0a2&x-expires=2107598400&x-signature=PUR69%2FLbd6lqI2uuYWBrS4W6W04%3D&from=876277922"),
    ("[点火]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/3bb9834bd95d4a5ba305ca2d788bd62e?lk3s=343af0a2&x-expires=2107598400&x-signature=oCkNpjkw%2Br68RawGA99p%2FNhb75A%3D&from=876277922"),
    ("[哭哭]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c380b32e707b43a2967ee7b492771c0f?lk3s=343af0a2&x-expires=2107598400&x-signature=YUHXJq4GJ%2FVd%2B248f7%2BJG0JnIQo%3D&from=876277922"),
    ("[吐舌小狗]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e4fb11ce2e2b432483ef58e058be6e0d?lk3s=343af0a2&x-expires=2107598400&x-signature=dTU3ezszTPDgn6%2Bg4g25Q1Doy3I%3D&from=876277922"),
    ("[送花]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ff736698b03446d19ae05cbd6cc45256?lk3s=343af0a2&x-expires=2107598400&x-signature=pOsufh1B%2F9vzQcrGbEI6n4nKHN4%3D&from=876277922"),
    ("[爱心手]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/7f50f1d4d0c74571b1a60eba9b41a4d7?lk3s=343af0a2&x-expires=2107598400&x-signature=UC1AbcCjXX4pxwiD%2FhWN%2FtsHaBg%3D&from=876277922"),
    ("[贴贴]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c3dee11223784da3a2ed524d94bb2ce8?lk3s=343af0a2&x-expires=2107598400&x-signature=QKTGJZDUrt%2BH%2B6oESVbdfl6hstA%3D&from=876277922"),
    ("[灵机一动]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/801127f060844405b0f5e00bd01cb8ba?lk3s=343af0a2&x-expires=2107598400&x-signature=iJJkD8Ha3ov24X68sjJNw3zKP2Q%3D&from=876277922"),
    ("[耶]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/f00c1c8054ff41768994256236d305b1?lk3s=343af0a2&x-expires=2107598400&x-signature=h%2Be%2BCejL3Dy%2BHvqLYo1T18Z58MM%3D&from=876277922"),
    ("[打脸]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d00f39c3d5d54144a395ad4d7f8d4489?lk3s=343af0a2&x-expires=2107598400&x-signature=5b01r5%2BfiPpcFSVn2%2BYTfZSESrI%3D&from=876277922"),
    ("[大笑]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ce993ad237174993a2ed8de550a63772?lk3s=343af0a2&x-expires=2107598400&x-signature=gbtHTt72mZ5C0y6Qa4lMZSF3u2I%3D&from=876277922"),
    ("[机智]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ca113e21412d4609ae38032b3befddb9?lk3s=343af0a2&x-expires=2107598400&x-signature=iXEQMOeTyEZ8gDbuWHkaitUlfWI%3D&from=876277922"),
    ("[送心]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/72211d3eadb64791a967f43ab340a55a?lk3s=343af0a2&x-expires=2107598400&x-signature=wx6ppVHrv%2Bpyx3ln8rFAqxKoAlw%3D&from=876277922"),
    ("[666]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/11a083f1a213461f859370ccbce074df?lk3s=343af0a2&x-expires=2107598400&x-signature=EprMInJap1R%2BpukCxEdVh9RyPhQ%3D&from=876277922"),
    ("[闭嘴]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d32f14b5edfd4489a4ea736a8ad39741?lk3s=343af0a2&x-expires=2107598400&x-signature=Zyy6oD3%2BEmI9OtalYES2nMdL3gM%3D&from=876277922"),
    ("[来看我]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/27059cc0891649a8b2b0860b5b08f540?lk3s=343af0a2&x-expires=2107598400&x-signature=w7Wc12VwWjhx50Axp9aPz3BGAk0%3D&from=876277922"),
    ("[一起加油]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/632214f7625a41ec8b558961929153f8?lk3s=343af0a2&x-expires=2107598400&x-signature=XCMKeK2nUl8JHtYqXJLMBa8C9u0%3D&from=876277922"),
    ("[哈欠]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/8ef4e9f6ef36449dab4c5ecde36f7d6b?lk3s=343af0a2&x-expires=2107598400&x-signature=46N5nAFffRXV7g9Ijv%2BBBaQa2rQ%3D&from=876277922"),
    ("[震惊]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/7181d20e807f4c5787f484531d1d8468?lk3s=343af0a2&x-expires=2107598400&x-signature=if1QVzrn5B0ylj89jP6h3qR0EO8%3D&from=876277922"),
    ("[晕]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/2af8cb49d2854197b7dd9b87f9dd106b?lk3s=343af0a2&x-expires=2107598400&x-signature=9G14gk4f7JSNhwB4Ns82LMqn42w%3D&from=876277922"),
    ("[衰]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/aa5c7f4a1d0c430a94934287cacd3c17?lk3s=343af0a2&x-expires=2107598400&x-signature=ssDgWm6SmhQWt2Z1CD%2FhMpp4W6M%3D&from=876277922"),
    ("[困]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/23cdce75a6d64bd8bb7ff87037db1be0?lk3s=343af0a2&x-expires=2107598400&x-signature=GnDzv4gpxbvxabbkjoe9yaw29NQ%3D&from=876277922"),
    ("[疑问]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/9ea78ef420fa4bf1b7e544a01e75b830?lk3s=343af0a2&x-expires=2107598400&x-signature=Q1LKLBwKRx4mU6oBzgqTiUdbRcM%3D&from=876277922"),
    ("[泣不成声]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/7fb67c323a0d410ea5573d4825e347eb?lk3s=343af0a2&x-expires=2107598400&x-signature=EPRJsASmnAB84lIPW5hhMjklR0Q%3D&from=876277922"),
    ("[小鼓掌]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/8f19f0db21324c7f9ce7b2dca984a309?lk3s=343af0a2&x-expires=2107598400&x-signature=WrK9UXvhUwFVxIfpPFYzkIhGOw8%3D&from=876277922"),
    ("[大金牙]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/b94090121f3e4549a3bee84e00515ed0?lk3s=343af0a2&x-expires=2107598400&x-signature=2G3Nny0%2FbQkUXlZSWeK6k0jX2GI%3D&from=876277922"),
    ("[偷笑]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/817c931baafa4d06a120a8d67973b6f0?lk3s=343af0a2&x-expires=2107598400&x-signature=fmPI2OFvgWQRvXDuXRemR02%2FC08%3D&from=876277922"),
    ("[石化]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/88746458dcbd47b1aa801e3823e6c9a2?lk3s=343af0a2&x-expires=2107598400&x-signature=VNAclyImOMZYCWQaePhRMyggI6s%3D&from=876277922"),
    ("[思考]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c3e345069adf42f58036c349ecc20a00?lk3s=343af0a2&x-expires=2107598400&x-signature=9d9w0ULATqR3YACyWk5ATcv%2BmdY%3D&from=876277922"),
    ("[吐血]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/331299e25af844a38800ec75d8dd0a16?lk3s=343af0a2&x-expires=2107598400&x-signature=TN26luv8B8%2FvM8YVicVdCfDn2hc%3D&from=876277922"),
    ("[可怜]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/1369a30daa7d45d6b3fa5ab241938fd2?lk3s=343af0a2&x-expires=2107598400&x-signature=bqPfs59KcmZgKhPUgo%2FcNyZb72w%3D&from=876277922"),
    ("[嘘]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/7c02d77ba7b44cfda223941529ccb2e6?lk3s=343af0a2&x-expires=2107598400&x-signature=%2FuazSbOjId5FuxTVGMJTRZ8%2Fh4A%3D&from=876277922"),
    ("[撇嘴]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/784ef77ac9de4e4990a607166856cd38?lk3s=343af0a2&x-expires=2107598400&x-signature=KV1xSi8PZc96REyAnBBKi2429FY%3D&from=876277922"),
    ("[笑哭]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e4f0c86449754bab8ae2cefe6317ceee?lk3s=343af0a2&x-expires=2107598400&x-signature=gS5NydxhXX9Ks36FHV7yGkpjaRk%3D&from=876277922"),
    ("[奸笑]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/6ac6247beb3a41d9b9e0e982e0225506?lk3s=343af0a2&x-expires=2107598400&x-signature=RASmIfyuBnJJzbcbNKqsm76EDQs%3D&from=876277922"),
    ("[得意]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/b1b52b6e940a4ef8907819eb8e871c21?lk3s=343af0a2&x-expires=2107598400&x-signature=cIR3W8DDnf%2F%2BIBqK07ukmhO1pr4%3D&from=876277922"),
    ("[憨笑]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/fceeae50c04b4343b44055ba9f9bb1a3?lk3s=343af0a2&x-expires=2107598400&x-signature=O%2B%2BPHNNs8Qeg6R16LaJDNnEIDF0%3D&from=876277922"),
    ("[坏笑]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/eab59a94674f40358b412586f148aac6?lk3s=343af0a2&x-expires=2107598400&x-signature=kwHPpkZNPr8YvYmUul0IkeVJ%2Bpg%3D&from=876277922"),
    ("[抓狂]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e7ffd9db28e3455195872ebf666d2c66?lk3s=343af0a2&x-expires=2107598400&x-signature=tXptuXTXkU6ryr9mz62Ub6XEnDk%3D&from=876277922"),
    ("[泪奔]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/20dbe8334dd64d028f943abc2ccde4d9?lk3s=343af0a2&x-expires=2107598400&x-signature=P0YvLy9oh9zXED2Nvt1UVIN%2F85Y%3D&from=876277922"),
    ("[钱]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/9a45bb9c0b8a4963b858846b079cfe2f?lk3s=343af0a2&x-expires=2107598400&x-signature=F7nVFSjSU79ZYVLclUxoEQZyuZs%3D&from=876277922"),
    ("[恐惧]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c12d025f50a047c2b064ce5f1a196f94?lk3s=343af0a2&x-expires=2107598400&x-signature=LRWwQy8lsMUfUPDLU3vhYw0BaXA%3D&from=876277922"),
    ("[愉快]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/62266cefe5fe4422aceaeaeed9072b3b?lk3s=343af0a2&x-expires=2107598400&x-signature=Jn%2FLkZqIPzQSI6TgZa36zh1gSV0%3D&from=876277922"),
    ("[快哭了]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/79df79563eaf424e9eb7a26558236ff7?lk3s=343af0a2&x-expires=2107598400&x-signature=Wk%2FWRFm5nZNZsiuopcRo30d%2BYiM%3D&from=876277922"),
    ("[翻白眼]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/0e40da06368145848f7585edc937f34e?lk3s=343af0a2&x-expires=2107598400&x-signature=agFzSupX%2FCcSWtIg0Saldb00uNQ%3D&from=876277922"),
    ("[互粉]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/cb46843009fe47808953af2c9ab2fb9a?lk3s=343af0a2&x-expires=2107598400&x-signature=k1wmCmIW4ndtoloLsWkzRp3Ra5I%3D&from=876277922"),
    ("[我想静静]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/95d5d919b99c43f29d2fbc660ec873f0?lk3s=343af0a2&x-expires=2107598400&x-signature=GmeS9B0teyeI4ifDTKCygzRLm6g%3D&from=876277922"),
    ("[委屈]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/2f7509f2cbe248889f279d19ea3fd649?lk3s=343af0a2&x-expires=2107598400&x-signature=JJXnCdarqxgttrAmvBAv9LLFl7g%3D&from=876277922"),
    ("[鄙视]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/5c13cbb44f334122a9cd7cf4bcc6598e?lk3s=343af0a2&x-expires=2107598400&x-signature=9NCEIRByaKOrOpV94wJ58DCBSbs%3D&from=876277922"),
    ("[飞吻]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/6dcb7560c1c84d45b4abe2cb37ae7afb?lk3s=343af0a2&x-expires=2107598400&x-signature=DMeQMmFoCs1Es5HIU8ei3KgYzqs%3D&from=876277922"),
    ("[再见]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/cae63f89c3eb478f8d1cca893b1b1a0c?lk3s=343af0a2&x-expires=2107598400&x-signature=a0FmODg27oBkvVTTOFbDakkRJd8%3D&from=876277922"),
    ("[紫薇别走]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/1d921b6eff48473f872fa7d278d26926?lk3s=343af0a2&x-expires=2107598400&x-signature=ZoYJv5y1x7cg0NIdb4n8to%2BApXU%3D&from=876277922"),
    ("[听歌]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/82bed7a3182b4c6db21ca39417359fa1?lk3s=343af0a2&x-expires=2107598400&x-signature=3crdq1LVQeDZnK1IY%2Bv%2FSp5oypo%3D&from=876277922"),
    ("[求抱抱]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/de99b54c6be24f73a5aaef8366a55e99?lk3s=343af0a2&x-expires=2107598400&x-signature=H8bmxwf6CNK4HjQkSzDeA52slko%3D&from=876277922"),
    ("[绝望的凝视]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/19f6a9449e714d85bb393794daaf6d58?lk3s=343af0a2&x-expires=2107598400&x-signature=zpdUfW0HUT4uGKbE7OxwsalyBUY%3D&from=876277922"),
    ("[不失礼貌的微笑]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/b7b842ba92e14fb8a8f328f25db91276?lk3s=343af0a2&x-expires=2107598400&x-signature=GjftwZH0H6pwXupZ4vZ5Jz3GE00%3D&from=876277922"),
    ("[不看]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/626f19e473d94e95b21b67f098599281?lk3s=343af0a2&x-expires=2107598400&x-signature=CpP2qBjBamipkB5mqrBQj0aecWI%3D&from=876277922"),
    ("[裂开]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e8c40bd4201e4afda065c55688971a2f?lk3s=343af0a2&x-expires=2107598400&x-signature=amL5AWVdzGH1rviGutto2d07TyY%3D&from=876277922"),
    ("[干饭人]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/0b0adfdffaea4c62a73302ae44d67a66?lk3s=343af0a2&x-expires=2107598400&x-signature=UaKNz7ZsEU6zCrx%2B4bAYLuneFUc%3D&from=876277922"),
    ("[庆祝]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/9c1325e3650a4a4d96d8e299406d9d68?lk3s=343af0a2&x-expires=2107598400&x-signature=VfLXqldVhuN%2Fxa1QgvrnPuQuxDk%3D&from=876277922"),
    ("[吐舌]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e577535321324e68a0cc8fcff1a2f421?lk3s=343af0a2&x-expires=2107598400&x-signature=9WGnMUUyxJMmt0JuJuxsZ%2BtArjw%3D&from=876277922"),
    ("[呆无辜]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/98c368cc39b74b94bf7923b6d9c479b9?lk3s=343af0a2&x-expires=2107598400&x-signature=Hhg24u0dEYf%2FBIXUflfuAW4PiVg%3D&from=876277922"),
    ("[白眼]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/a9d1ba597042412f9275369807147bee?lk3s=343af0a2&x-expires=2107598400&x-signature=jGkxq%2Bvp6IFHDiWnwlb3GL8Yk7w%3D&from=876277922"),
    ("[猪头]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/4296ea156ee6479e9ad5c1381ec73cca?lk3s=343af0a2&x-expires=2107598400&x-signature=%2FdoCenOFnZurCnlfMJ%2BCWhCT5YQ%3D&from=876277922"),
    ("[冷漠]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ba1d020f28a749e388fb1d15e52ac4ae?lk3s=343af0a2&x-expires=2107598400&x-signature=LBg9ztncb%2BQa9GQE1b7YssY%2BYNY%3D&from=876277922"),
    ("[暗中观察]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/3cf77301823a4e969cc4c0a04d245f3d?lk3s=343af0a2&x-expires=2107598400&x-signature=0IRICS9eRA2sfCMTWQaUlLxCEEU%3D&from=876277922"),
    ("[二哈]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/2ddc8ae48fae4a4fb3767f666bb79d95?lk3s=343af0a2&x-expires=2107598400&x-signature=DtlmzZNMgRwRVM7rlu8Tk0BfK%2B0%3D&from=876277922"),
    ("[菜狗]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/62baecf5a0084194ac383d3d199ab597?lk3s=343af0a2&x-expires=2107598400&x-signature=x4%2BiQvQ1Cv%2B8VnvB%2FA0E9w2AyMA%3D&from=876277922"),
    ("[黑脸]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/b96c76ac689f44d09537583ca2357672?lk3s=343af0a2&x-expires=2107598400&x-signature=2xtuIf0q5eCinwKJMXVj8XdG6dg%3D&from=876277922"),
    ("[展开说说]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/30f0c01ef9d24144a8ae05351485fe18?lk3s=343af0a2&x-expires=2107598400&x-signature=IyttqWy4us2YeGPhbhcONUH62dY%3D&from=876277922"),
    ("[蜜蜂狗]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d336f83b827b407d872bc48861a44c70?lk3s=343af0a2&x-expires=2107598400&x-signature=8W8CmY4AxQLTpAD%2FNzw%2Fo3KwEhE%3D&from=876277922"),
    ("[柴犬]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/764a5db2a67242c189f5fdabb1c75648?lk3s=343af0a2&x-expires=2107598400&x-signature=xTFZbi6TIsX6waCwYUvJ%2FwVPItQ%3D&from=876277922"),
    ("[摸头]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/10790e118cbc4d13b48cdc19c1eecb96?lk3s=343af0a2&x-expires=2107598400&x-signature=aXf88X79s1m%2BsqhVPsFhPmEEFAc%3D&from=876277922"),
    ("[皱眉]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d143738426054c9f88657ee97b779643?lk3s=343af0a2&x-expires=2107598400&x-signature=4%2BQUrfvYOoYxDSGcnUpPeYxgpLc%3D&from=876277922"),
    ("[擦汗]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/0f7be11419c44d1ab158bbafa666101c?lk3s=343af0a2&x-expires=2107598400&x-signature=TVo%2B2lzlNCWSc1yd4%2B0lPZHAcrQ%3D&from=876277922"),
    ("[红脸]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/15efff0277f74e5b9e2b12c984eac159?lk3s=343af0a2&x-expires=2107598400&x-signature=qhLJeuGie0S%2BU%2BPnE3Om3a3zp38%3D&from=876277922"),
    ("[做鬼脸]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e8d099b1dc5b41b0b8535b47747a94f4?lk3s=343af0a2&x-expires=2107598400&x-signature=ZnkZNc4i9%2B5oHwtHWWo4KOAoC6M%3D&from=876277922"),
    ("[强]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/0b815bcdb647471b9281e3105d8d6c8e?lk3s=343af0a2&x-expires=2107598400&x-signature=Zc%2FWv2nG4znNzNN839vmBDWNVNk%3D&from=876277922"),
    ("[如花]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/dd44ccdacbe6444a9515bdca3fb56d5f?lk3s=343af0a2&x-expires=2107598400&x-signature=Rhmf5aqnOEp6kYZ78x%2F%2BRkaZ92M%3D&from=876277922"),
    ("[吐]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c0157bfb1fc548d097933c039d6952ae?lk3s=343af0a2&x-expires=2107598400&x-signature=hDguH2GOYn7ucg%2Bo1A7nNtDuJ7Q%3D&from=876277922"),
    ("[惊喜]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e718e4d7913c4bcf9c49560ff96386e9?lk3s=343af0a2&x-expires=2107598400&x-signature=VhpwIxRVTODj8d1FbOI%2BsS4I7ck%3D&from=876277922"),
    ("[敲打]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/8067eb30b0d74ad29c15a8c5c7b11230?lk3s=343af0a2&x-expires=2107598400&x-signature=9YeHgHVYDI0D%2B%2FUICpm3a0%2BqVso%3D&from=876277922"),
    ("[奋斗]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/fb3fb08ab5204f2a83086d782944882d?lk3s=343af0a2&x-expires=2107598400&x-signature=OuidhgbEZk9M69TpmXum4SB0uR8%3D&from=876277922"),
    ("[吐彩虹]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/0878b09fe3fa4d4a8f47c63748cf7762?lk3s=343af0a2&x-expires=2107598400&x-signature=Os1yd12y2Mfi%2Bp%2Bl7qdUEPcBpR8%3D&from=876277922"),
    ("[大哭]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/53246f7d51fa42e5b48b99c8074ca607?lk3s=343af0a2&x-expires=2107598400&x-signature=qPbpMxcvusuJFI6oZyB%2BKQhYUrY%3D&from=876277922"),
    ("[嘿哈]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/af4e2e63b51f4d66a060ff0a42d0098b?lk3s=343af0a2&x-expires=2107598400&x-signature=smVnlteW2ew2FEFUmVeh2xLVIFg%3D&from=876277922"),
    ("[惊恐]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/fd2f5745edbd4dadb6014096965d1c6c?lk3s=343af0a2&x-expires=2107598400&x-signature=JVeKoamBbZ1WNDQnXsA0VDVJopM%3D&from=876277922"),
    ("[囧]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/4cd5a1e2c43341a9b4ac95ace6ed913e?lk3s=343af0a2&x-expires=2107598400&x-signature=BAmbFJ7NMjRWcAHi%2FOXXcgmXOes%3D&from=876277922"),
    ("[难过]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/697dc91cd453495d988628058582fed3?lk3s=343af0a2&x-expires=2107598400&x-signature=Q3w4D%2FaPmCd3DB9DJP9yssJF9Cw%3D&from=876277922"),
    ("[斜眼]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/63a00ad586eb4f9e81369a7e693b778b?lk3s=343af0a2&x-expires=2107598400&x-signature=CA4ddA288ruZ7EE5IWoEbTOuR1w%3D&from=876277922"),
    ("[阴险]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/628bc8956092489399730d0c8178de5b?lk3s=343af0a2&x-expires=2107598400&x-signature=NFgunCfAGt1U1AjIsO5bv6T%2BpJA%3D&from=876277922"),
    ("[悠闲]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/989818a338bd4d718f0afc47f7c76a4c?lk3s=343af0a2&x-expires=2107598400&x-signature=KPQsSoTirTs93bIdWHb6HXGhW%2FA%3D&from=876277922"),
    ("[咒骂]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/44802ec1a8bd4ff2aac38cfcf97201cb?lk3s=343af0a2&x-expires=2107598400&x-signature=c8YDv%2BNEQCvUR50v7ygr5z9bowY%3D&from=876277922"),
    ("[吃瓜群众]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/2e2059714acb489483735cbe63ff7dbc?lk3s=343af0a2&x-expires=2107598400&x-signature=s1vQ7lWeHHXMdeQbhBTx5DXX1ws%3D&from=876277922"),
    ("[绿帽子]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d23e058bab744349ac636c45e9a3687f?lk3s=343af0a2&x-expires=2107598400&x-signature=VBbOeZMhHypk2mEw2ulHluHpss0%3D&from=876277922"),
    ("[敢怒不敢言]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/38b34096e69c41119b8d50cfd3a66882?lk3s=343af0a2&x-expires=2107598400&x-signature=NHKKYQNRTuuI5BK%2Bbsu2ooqGuLA%3D&from=876277922"),
    ("[求求了]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/3b99deef770044d79182c18a854f4f27?lk3s=343af0a2&x-expires=2107598400&x-signature=OXtxzdmdXQLUCOxRszbxWk0%2FeHw%3D&from=876277922"),
    ("[眼含热泪]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/daf0e01ed3404b8e88898f690533bb76?lk3s=343af0a2&x-expires=2107598400&x-signature=NP%2BPXELFDFx4YStl3N%2F44TTX6Iw%3D&from=876277922"),
    ("[叹气]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d7c541c323de4272acf862f77bb8b8a2?lk3s=343af0a2&x-expires=2107598400&x-signature=7rHMb31C4eF34ZixXRbAZ5TVkE8%3D&from=876277922"),
    ("[好开心]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/9b931359a63a42f693fdabe5934e95a9?lk3s=343af0a2&x-expires=2107598400&x-signature=os3r5IHeHG2phAQMAo9N6mYsgHU%3D&from=876277922"),
    ("[不是吧]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/a854fc87af894fddb1e36f97867c8169?lk3s=343af0a2&x-expires=2107598400&x-signature=fYI%2B1w9hXzYBafdhMFJ5r8CH3U8%3D&from=876277922"),
    ("[鞠躬]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/93ffc02b07174d15a0d602b7a4cbb87f?lk3s=343af0a2&x-expires=2107598400&x-signature=Jo18H9SfyrtNqy2UBghYidrLU68%3D&from=876277922"),
    ("[躺平]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/25625ce0678448fc9c556bd1ebcf638c?lk3s=343af0a2&x-expires=2107598400&x-signature=m1pBp1bxkPbUUsfuLeLL%2BADu%2Bzk%3D&from=876277922"),
    ("[九转大肠]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ea89e25c77dd423d8403d20740f23bb7?lk3s=343af0a2&x-expires=2107598400&x-signature=%2BKelejIrZIIqv0%2Fpay9Y6kT5NMM%3D&from=876277922"),
    ("[不你不想]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/b4845baf417a404488e955464208cc3c?lk3s=343af0a2&x-expires=2107598400&x-signature=CE5%2FsfiyXrIUoWkRE9a5uWyETfA%3D&from=876277922"),
    ("[一头乱麻]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/db393c6b9bba40f3b37d4e079d1cbf1e?lk3s=343af0a2&x-expires=2107598400&x-signature=L%2Fke9lWNGxkCk%2Fq6rmRMOMtOIXY%3D&from=876277922"),
    ("[kisskiss]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/f971f6f859b24829a15196c5a0738df1?lk3s=343af0a2&x-expires=2107598400&x-signature=tBFQvJXRrxosvseuqjMm4Zev4u4%3D&from=876277922"),
    ("[你不大行]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/0f2d07ea48a94bf0a57818056392bb42?lk3s=343af0a2&x-expires=2107598400&x-signature=OK6Sd%2FrV4kOSDCnJjD7XdvcSefo%3D&from=876277922"),
    ("[噢买尬]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/af75834bf58e44c88b1825f85d50b7da?lk3s=343af0a2&x-expires=2107598400&x-signature=rdCCKbEjFx44nU%2BS4MP6ldE7xTI%3D&from=876277922"),
    ("[宕机]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/561341b97e7844148b6f040241357122?lk3s=343af0a2&x-expires=2107598400&x-signature=qjjVAnShyvR4UavfELR6LZvW%2Fek%3D&from=876277922"),
    ("[苦涩]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e72ce46a6ab640b38c7686f4b77fb7e4?lk3s=343af0a2&x-expires=2107598400&x-signature=B54HElhAd2KjNASBWrP74GLARmk%3D&from=876277922"),
    ("[逞强落泪]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/67b9bcd2e1d64888bf57fa433e5b4717?lk3s=343af0a2&x-expires=2107598400&x-signature=brTYoH5OnPSL5X%2Ftxw3LXVUtFlM%3D&from=876277922"),
    ("[求机位-黄脸]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/66e8109018b64af1b87ce68ff2bfc18e?lk3s=343af0a2&x-expires=2107598400&x-signature=yDGhNGN4J0VlaEPOHUbB%2B5LS8MA%3D&from=876277922"),
    ("[求机位3]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ec3d99650c114cb49f22cda9ce06d25f?lk3s=343af0a2&x-expires=2107598400&x-signature=KbQKBoy4GZeBHAstMMV%2FH1Ci%2FZo%3D&from=876277922"),
    ("[点赞]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/8e7e1b35d32b4623a0240552dc784b0f?lk3s=343af0a2&x-expires=2107598400&x-signature=7FzmVzr1Cs1SdIDNddOUYBlM%2BN0%3D&from=876277922"),
    ("[精选]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/8d72402dd91a4a3a8cf4591b266ddb14?lk3s=343af0a2&x-expires=2107598400&x-signature=6ESLPCaal2aT1fHqTCuL50eg3KU%3D&from=876277922"),
    ("[强壮]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/41a493d326e7475fb8f1ef0c614dbf25?lk3s=343af0a2&x-expires=2107598400&x-signature=uu3Vl8MHkxM9GP2pIeI7QNLd754%3D&from=876277922"),
    ("[碰拳]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/2bba2a8b361e467288d796c1581fec60?lk3s=343af0a2&x-expires=2107598400&x-signature=LAh%2BkEZWbsos27Q%2Bft4I7b0e1OA%3D&from=876277922"),
    ("[OK]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/28dd2b330ea74d4cac2388f617177fe1?lk3s=343af0a2&x-expires=2107598400&x-signature=G9WOEZaIyYanlxP7reRNwjdagWM%3D&from=876277922"),
    ("[击掌]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d3f83268e073468fbe8759638beb42ef?lk3s=343af0a2&x-expires=2107598400&x-signature=DGCIMk3DVeD%2F55KoCXdBttLt%2BAk%3D&from=876277922"),
    ("[左上]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/cf670dd2a4c2487181ee834aa0b048fa?lk3s=343af0a2&x-expires=2107598400&x-signature=rsnCx0Zv1DYvfAYji5xuxrm5Z0A%3D&from=876277922"),
    ("[握手]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/4550a48b841144d7b37fff3d02ec8a25?lk3s=343af0a2&x-expires=2107598400&x-signature=xbrRmFn72czUYnUAKA%2BApyON8GI%3D&from=876277922"),
    ("[抱拳]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/5c6a7e331b7441ecb615e0adab43935a?lk3s=343af0a2&x-expires=2107598400&x-signature=MhvAK30iXyTjCy6OrWjQSYV3pvc%3D&from=876277922"),
    ("[勾引]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/6db49f314c1d4754a8205c3231edd396?lk3s=343af0a2&x-expires=2107598400&x-signature=n9ciKLXvgYMeFpP7IIkGBQj7G0I%3D&from=876277922"),
    ("[拳头]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/5bede8c4134b4be798c924faee784650?lk3s=343af0a2&x-expires=2107598400&x-signature=i51o2%2BPiYOl%2Bcqgp7QckaRJ1weA%3D&from=876277922"),
    ("[弱]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/5028f8d3638a488b987008c384745afc?lk3s=343af0a2&x-expires=2107598400&x-signature=39xzgePAU3UoZyYBD0rZpXNwHXs%3D&from=876277922"),
    ("[胜利]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/85abaf2fa4b940879a7b3bfdb45c3299?lk3s=343af0a2&x-expires=2107598400&x-signature=V07vAj7Ji7KUN%2BAvV%2F6yvRKhSJA%3D&from=876277922"),
    ("[右边]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/11aadc9ed7b643279c38f94e8ed347c0?lk3s=343af0a2&x-expires=2107598400&x-signature=fqg%2FrftBZap4qjlbHShsyUUb4OA%3D&from=876277922"),
    ("[左边]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/bed344e70c214bf281db6a7944ef909a?lk3s=343af0a2&x-expires=2107598400&x-signature=nVixSeL57hQ9CGhzAEsMFvM9DjY%3D&from=876277922"),
    ("[嘴唇]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/b1b3824e7b6c482b8d52b1c3b5577849?lk3s=343af0a2&x-expires=2107598400&x-signature=aLG03gPJrJyscUNVMd923uxuX40%3D&from=876277922"),
    ("[心碎]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/371bb866809f454597ef538f604bd25a?lk3s=343af0a2&x-expires=2107598400&x-signature=3Au%2B3vJL8M0C0ZMy8y1bVsyrmpU%3D&from=876277922"),
    ("[凋谢]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c93a47ad594b4be3a8c288aff0d7543b?lk3s=343af0a2&x-expires=2107598400&x-signature=FXs%2BZeTvbo0sdSBh5ebCmzEWlXw%3D&from=876277922"),
    ("[愤怒]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/6dd1d010b5fd4f5197c1ecad3ce6796b?lk3s=343af0a2&x-expires=2107598400&x-signature=6T4EkNdsK1KvHH%2Fyz9ms3%2F6GH1c%3D&from=876277922"),
    ("[垃圾]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/d7d09280091445aabfd912bcca4d9a89?lk3s=343af0a2&x-expires=2107598400&x-signature=9ekRg55lRae9piliq0lV0bXKNKk%3D&from=876277922"),
    ("[啤酒]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/a8ae1c4c2e0f467dbff1ba0964e0175d?lk3s=343af0a2&x-expires=2107598400&x-signature=BzJQ867BazBca9X1LQAbGIWcajE%3D&from=876277922"),
    ("[咖啡]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/dcbcf5d7ca07490a950a37ff66a5be74?lk3s=343af0a2&x-expires=2107598400&x-signature=3P8U%2BxeAbbJ%2FZroclMjL4pfzCws%3D&from=876277922"),
    ("[蛋糕]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/1153a12fbb514977b3a5349d3dcc509b?lk3s=343af0a2&x-expires=2107598400&x-signature=eNbrb8vDBeA46c3ApHaFzV9A1F4%3D&from=876277922"),
    ("[礼物]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e8e086e0f6544f9b87117abebd96e840?lk3s=343af0a2&x-expires=2107598400&x-signature=DB%2FUsfLowrEoCjkixqULefEcJ0Y%3D&from=876277922"),
    ("[撒花]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/8cefd1b8c16b412298657b6e1d81f8ab?lk3s=343af0a2&x-expires=2107598400&x-signature=bDWFaL4991INFe6ntuc1HkDKl%2Fc%3D&from=876277922"),
    ("[加一]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/496076e82fd74be793ab16d2940e8f8c?lk3s=343af0a2&x-expires=2107598400&x-signature=07LChOMWR%2FXPTEXjbVgllKjEKuc%3D&from=876277922"),
    ("[减一]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ffc25006163e4ecfa70968744d1be61e?lk3s=343af0a2&x-expires=2107598400&x-signature=gFTTEGH3uUGH3LVF3Ha8i6LOeR4%3D&from=876277922"),
    ("[okk]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/9309aa3f9bed475b88538346f56fc6e6?lk3s=343af0a2&x-expires=2107598400&x-signature=bGE7J7jhggMTYi%2BYIKnmyLLOH8M%3D&from=876277922"),
    ("[V5]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/cddffb522b2d421d81eb9da0f7f3cbb1?lk3s=343af0a2&x-expires=2107598400&x-signature=P%2BpUlFZIvTtIDq%2FTd7jKZlhtgT0%3D&from=876277922"),
    ("[绝]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/f1e1a02468b7420c841733c780ec2576?lk3s=343af0a2&x-expires=2107598400&x-signature=zyAQmmK7JZ0g87v6C4ypT0%2BcS30%3D&from=876277922"),
    ("[给力]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/5387fc1361634b579946fbac7c4ea5f4?lk3s=343af0a2&x-expires=2107598400&x-signature=aKmXz4UXkTytdNnFrfGanH00Qeg%3D&from=876277922"),
    ("[红包]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/3e78d79aa4964404bb78b445f34c78fd?lk3s=343af0a2&x-expires=2107598400&x-signature=%2FQaJpwiUU7PW0tMPDOGrru9JsdM%3D&from=876277922"),
    ("[屎]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/eae0730620d644bdbb91985bd9cfff4e?lk3s=343af0a2&x-expires=2107598400&x-signature=JB1aGnfP4pXxi4YHKFllduTJbJA%3D&from=876277922"),
    ("[发]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ee4f3e944a62429e8e963bd187d00536?lk3s=343af0a2&x-expires=2107598400&x-signature=Nsy80%2Fn3LiwhAvLLRA5%2B1Kq8b3w%3D&from=876277922"),
    ("[18禁]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/40724dd5538c474693ec54d34a14c613?lk3s=343af0a2&x-expires=2107598400&x-signature=qkMeWLTSrzDdsIrK3GM%2BN%2BLVask%3D&from=876277922"),
    ("[炸弹]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/a309a1e9a10049d88b1c9848f5f7b287?lk3s=343af0a2&x-expires=2107598400&x-signature=9VYayAfQh5udpzzrbr9BYqpxZbU%3D&from=876277922"),
    ("[西瓜]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/39ca333313da4187bd5651a5404aed26?lk3s=343af0a2&x-expires=2107598400&x-signature=c1ZZyI04Urphgi%2BydLkyffueFKg%3D&from=876277922"),
    ("[加鸡腿]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/1391aac43d004af986f2202f43253f94?lk3s=343af0a2&x-expires=2107598400&x-signature=T0n8K%2BxmCLoAvNV2unyWa%2BqI%2FG0%3D&from=876277922"),
    ("[握爪]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/966210d6153146e8b58686aa1cc763ca?lk3s=343af0a2&x-expires=2107598400&x-signature=YknKNzrDrV4w0PmlgmBKA7scHs4%3D&from=876277922"),
    ("[太阳]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/5c9e5b67fc524f14b4ae49b5977afd9d?lk3s=343af0a2&x-expires=2107598400&x-signature=0U9qHFYf1afY28IaecGSeLLAPcE%3D&from=876277922"),
    ("[月亮]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/cfa03e7f7b534eb2a9bc16fec54ed23f?lk3s=343af0a2&x-expires=2107598400&x-signature=PkjPXQAxNnjnJ1RpHOa8QBfW1EQ%3D&from=876277922"),
    ("[给跪了]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/21d2a8bbe630496d88c03fa9179b17cb?lk3s=343af0a2&x-expires=2107598400&x-signature=aBhXpLvCEG%2BCP8qJ11xJHcp7FFw%3D&from=876277922"),
    ("[蕉绿]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ac2d04da5bf54c8bb12628510d8718ba?lk3s=343af0a2&x-expires=2107598400&x-signature=qQDOpRy9JH6zpIBXMRlTJVMwUFU%3D&from=876277922"),
    ("[扎心]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e6121879b6de4bd08d35a312574f6563?lk3s=343af0a2&x-expires=2107598400&x-signature=hkEk72aPz34W4Jmy38tlcA4f9cc%3D&from=876277922"),
    ("[胡瓜]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/5f3bb76347cd49e4935300b507353f68?lk3s=343af0a2&x-expires=2107598400&x-signature=%2FixBO%2FOjxdQ87vrrQrV6j89TWrA%3D&from=876277922"),
    ("[打call]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/31a1efcf7c97414fae43d1d08058b0ee?lk3s=343af0a2&x-expires=2107598400&x-signature=XwL88xMU6u6ort5GFTUlt0zv7bc%3D&from=876277922"),
    ("[栓Q]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/a948fa11ae344a1d91276235ab6bf70b?lk3s=343af0a2&x-expires=2107598400&x-signature=zrseaWxC81i4oZREByEz6i6IQuw%3D&from=876277922"),
    ("[雪花]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/5144febc02ad42c082b83980d9159e13?lk3s=343af0a2&x-expires=2107598400&x-signature=ViT4c3uTbyH0RbkILYWn81VkksM%3D&from=876277922"),
    ("[圣诞树]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/9d3184f19a0042f2886922fd6d1b6823?lk3s=343af0a2&x-expires=2107598400&x-signature=bowrJIJKnTtmIoraiu2I6%2FW3CMA%3D&from=876277922"),
    ("[平安果]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/0855a7b63f1f437db4eaa3519d5dd4d5?lk3s=343af0a2&x-expires=2107598400&x-signature=u6n%2BuGj4f4ZwlZ4zAW0orjwqE80%3D&from=876277922"),
    ("[圣诞帽]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/71d0ea5435d443519eafc2d72eee07c7?lk3s=343af0a2&x-expires=2107598400&x-signature=xZuj11xnqXvgeEiXJiB0XHAuRTM%3D&from=876277922"),
    ("[气球]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/2eb779c7734345979bd3f866989a167f?lk3s=343af0a2&x-expires=2107598400&x-signature=EbDbwLwZ%2BywZdK9A79kiBQxnHo4%3D&from=876277922"),
    ("[烟花]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/e679017985b54d19b23668fc3437a1a1?lk3s=343af0a2&x-expires=2107598400&x-signature=hM5BrFu%2FWiAWkSYr6muAZn5LcW0%3D&from=876277922"),
    ("[福]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c5dd439d89754e4aa6c553a244aacc4b?lk3s=343af0a2&x-expires=2107598400&x-signature=sgJasDpJBkGpLNoxHuMteII8jAs%3D&from=876277922"),
    ("[candy]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/cce110c8f9f74a898a21ab413fb6cc63?lk3s=343af0a2&x-expires=2107598400&x-signature=cJFyyxdUTc6CnnZr9%2FW98LXEGO4%3D&from=876277922"),
    ("[糖葫芦]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/f99e62388e6c4553974f1fe44f602456?lk3s=343af0a2&x-expires=2107598400&x-signature=hEHN8XW2cKTtJyg6vul7z3U%2FtJA%3D&from=876277922"),
    ("[鞭炮]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/237a828fd0964b2b9510c15de33383ad?lk3s=343af0a2&x-expires=2107598400&x-signature=X6nTYMElKkTKtcZrc9%2BVciXqGHQ%3D&from=876277922"),
    ("[元宝]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/6c0ebb50021a4b9e84cb5908be4eb5ef?lk3s=343af0a2&x-expires=2107598400&x-signature=3Q3P8mtfzk7ool%2FCyVfH8ywqrHg%3D&from=876277922"),
    ("[灯笼]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/a7a43e8805fc425990fed26d8be5b7b6?lk3s=343af0a2&x-expires=2107598400&x-signature=Q4tvc%2FyO5FoCjKbam%2F8H4zfd4s8%3D&from=876277922"),
    ("[锦鲤]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/f88e3e8d639b438aaa084549086fbb46?lk3s=343af0a2&x-expires=2107598400&x-signature=HcKp060x5fjWBSxiK0xi0saEQS8%3D&from=876277922"),
    ("[巧克力]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c6db9180292c47779624a865d80f67e7?lk3s=343af0a2&x-expires=2107598400&x-signature=ynLAql9EoDA6%2FGNbnvA7EC7HIPU%3D&from=876277922"),
    ("[戒指]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/f8eb6c5b5d6640cc82de8ecd4acd33d0?lk3s=343af0a2&x-expires=2107598400&x-signature=zrGdglIayLHbjk%2FGDNh%2BYkglrr4%3D&from=876277922"),
    ("[棒棒糖]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/38fd079e306a40e4953bdf4a5d8a16db?lk3s=343af0a2&x-expires=2107598400&x-signature=vIzxXJHxR3GQOG%2F2UoWQlMhbbFE%3D&from=876277922"),
    ("[纸飞机]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/c0e6de9ee9d646d0a0d01831f3870787?lk3s=343af0a2&x-expires=2107598400&x-signature=UV14oGxSA3bIZBVtKzLbin5BcrQ%3D&from=876277922"),
    ("[粽子]", "https://p3-pc-sign.douyinpic.com/obj/tos-cn-i-tsj2vxp0zn/ce5e59e1376d440b98bb738c90e1a6e1?lk3s=343af0a2&x-expires=2107598400&x-signature=Psil8hI8DiVInji9RDQwCp33GgA%3D&from=876277922"),
];

static DOUYIN_EMOTICON_MAP: Lazy<HashMap<&'static str, &'static str>> =
    Lazy::new(|| DOUYIN_EMOTICONS.iter().copied().collect());

/// 从聊天正文提取标准表情码；无命中 -> None。
pub fn extract_emoticons(content: &str) -> Option<Vec<LiveMessageEmoticon>> {
    let mut result = Vec::new();
    let bytes = content.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] != b'[' {
            i += 1;
            continue;
        }
        let start = i;
        let mut j = i + 1;
        while j < bytes.len() && bytes[j] != b'[' && bytes[j] != b']' {
            j += 1;
        }
        if j < bytes.len() && bytes[j] == b']' && j > start + 1 {
            let token = &content[start..=j];
            if let Some(url) = DOUYIN_EMOTICON_MAP.get(token) {
                result.push(LiveMessageEmoticon {
                    name: Some(token.to_string()),
                    url: (*url).to_string(),
                    width: None,
                    height: None,
                    large: false,
                    emoticon_unique: None,
                });
            }
            i = j + 1;
        } else {
            i = start + 1;
        }
    }
    if result.is_empty() {
        None
    } else {
        Some(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn table_size_matches_web_panel() {
        assert_eq!(DOUYIN_EMOTICONS.len(), 214, "表情数量与网页端一致");
        assert!(DOUYIN_EMOTICON_MAP.contains_key("[呲牙]"));
        assert!(DOUYIN_EMOTICON_MAP.contains_key("[互粉]"));
    }

    #[test]
    fn extracts_known_codes_in_order() {
        let got = extract_emoticons("哈喽[微笑][赞]").expect("应提取到表情");
        let names: Vec<&str> = got.iter().filter_map(|e| e.name.as_deref()).collect();
        assert_eq!(names, vec!["[微笑]", "[赞]"]);
        assert!(got.iter().all(|e| e.url.starts_with("https://")));
        assert!(got.iter().all(|e| !e.large));
    }

    #[test]
    fn keeps_duplicates_and_ignores_unknown_or_plain_brackets() {
        let got = extract_emoticons("[呲牙][呲牙] [不存在] 普通文本").expect("应提取到两个");
        assert_eq!(got.len(), 2);
        assert!(got.iter().all(|e| e.name.as_deref() == Some("[呲牙]")));
        assert!(extract_emoticons("[不存在] 普通文本").is_none());
        assert!(extract_emoticons("没有方括号").is_none());
    }
}
