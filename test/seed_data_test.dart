import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/rich_text_codec.dart';
import 'package:novel_editor/data/models.dart';
import 'package:novel_editor/data/repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('seed sample data', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 内存数据库：绝不触碰真实数据文件。
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        pen_name TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        last_chapter_id TEXT,
        last_cursor INTEGER,
        cover_path TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE volumes (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sort INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        volume_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        outline TEXT NOT NULL DEFAULT '',
        sort INTEGER NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        char_count INTEGER NOT NULL DEFAULT 0,
        last_edited_at INTEGER NOT NULL,
        cursor_offset INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0,
        outline_edited_at INTEGER
      )
    ''');

    await db.delete('chapters');
    await db.delete('volumes');
    await db.delete('books');

    Future<String> createBook(String title, String penName) async {
      final now = DateTime.now();
      final b = Book(id: newId(), title: title, penName: penName, createdAt: now, updatedAt: now);
      await db.insert('books', b.toMap());
      return b.id;
    }

    Future<String> createVolume(String bookId, String name, int sort) async {
      final now = DateTime.now();
      final v = Volume(id: newId(), bookId: bookId, name: name, sort: sort, createdAt: now, updatedAt: now);
      await db.insert('volumes', v.toMap());
      return v.id;
    }

    Future<void> createChapter(String bookId, String volumeId, String title, String body, int sort) async {
      final content = RichTextCodec.deltaJsonFromPlainText(body);
      final now = DateTime.now();
      final ch = Chapter(
        id: newId(),
        bookId: bookId,
        volumeId: volumeId,
        title: title,
        content: content,
        sort: sort,
        charCount: _countChars(body),
        lastEditedAt: now,
      );
      await db.insert('chapters', ch.toMap());
    }

    final b1 = await createBook('江湖夜雨', '李慕白');
    final v1a = await createVolume(b1, '第一卷·风雨起', 0);
    await createChapter(b1, v1a, '第一章 雨夜来客',
        '　　三更时分，秋雨敲打着客栈的旧瓦。店小二早已睡下，大堂里只剩一盏孤灯。\n\n'
        '　　门轴吱呀一声响，冷风裹着雨丝灌进来。一个青衫客收了油伞，将斗笠摘下，露出一张风尘仆仆的脸。他腰间挂着一柄长剑，剑鞘上的铜扣已被磨得发亮。\n\n'
        '　　"掌柜的，"他声音不高，"可还有空房？"\n\n'
        '　　掌柜从柜台后探出头，见他衣着虽旧，气度却不凡，忙赔笑道："客官有礼，上房正好剩一间。"\n\n'
        '　　青衫客点头，将碎银拍在桌上，径直上楼。他不知道，此刻街对面的屋檐下，正有一双眼睛盯着他踏进门槛。', 0);
    await createChapter(b1, v1a, '第二章 古道相逢',
        '　　天色微明，雨已停了。青衫客牵马出镇，往西而行。\n\n'
        '　　古道两旁是连绵的枫林，落叶积了厚厚一层。走出十里，忽听前方传来兵刃相击之声。他纵马上前，只见一白衣女子正被三名黑衣人围攻。\n\n'
        '　　那女子剑法轻灵，如白练穿空，奈何寡不敌众，左肩已挂了彩。青衫客按剑不动，冷眼看了片刻，忽地拔剑出鞘。\n\n'
        '　　"三位，以多欺少，未免失了江湖体面。"\n\n'
        '　　为首黑衣人冷笑："多管闲事！"长刀劈面砍来。青衫客侧身让过，反手一剑，正中其腕。', 1);
    await createChapter(b1, v1a, '第三章 山中岁月',
        '　　自此，白衣女子便随他同行。她说自己叫沈青萝，家在江南，此番北上是为寻一位故人。\n\n'
        '　　两人不疾不徐，日行夜宿。山中秋意渐浓，红叶满径，溪水潺潺。青衫客话少，沈青萝却不嫌闷，总能在沉默里找出些话题来。\n\n'
        '　　"你那柄剑，剑身刻着半句诗，"她某日忽然问，"可是‘夜雨’二字？"\n\n'
        '　　青衫客握缰的手微微一顿，半晌才道："姑娘好眼力。"\n\n'
        '　　他没说下去，她也不再追问。山风过林，吹得满头落叶纷飞。', 2);
    final v1b = await createVolume(b1, '第二卷·故人归', 1);
    await createChapter(b1, v1b, '第四章 旧事重提',
        '　　进了洛阳城，繁华扑面而来。沈青萝要寻的故人，据说住在城南的旧巷。\n\n'
        '　　巷子尽头是一座荒废的小院，门上铜环生了绿锈。她叩了三声，无人应答。青衫客立在街角，看她立在门前，背影单薄。\n\n'
        '　　"人不在？"他问。\n\n'
        '　　"不在了。"她转过身，眼里没有泪，只有一种很淡的怅然，"其实我早猜到。只是不来一趟，总不死心。"\n\n'
        '　　青衫客沉默良久，将手中油伞递过去："走吧，我请你喝碗热汤。"\n\n'
        '　　那日洛阳下了入冬第一场雪。', 0);

    final b2 = await createBook('星河彼岸', '苏晚');
    final v2a = await createVolume(b2, '第一卷·启航', 0);
    await createChapter(b2, v2a, '第一章 离港',
        '　　"领航号"在轨道上滑行了三圈，才终于调正姿态。\n\n'
        '　　苏晚坐在舷窗前，看着母星在视野里缩成一颗蓝点。通讯频道里传来地面指挥的声音："领航号，你已获准离港。航向：开普勒-186f。预计航行时间，四十二年。"\n\n'
        '　　四十二年。她默念了一遍这个数字，转头看向冷冻舱——那里躺着六十九位旅人，将在低温中度过大半段旅程，只留她与另外两名轮值船员清醒。\n\n'
        '　　"开始进入跃迁通道。"她按下确认键，舰身轻轻一震，星群在窗外拉成长长的光带。', 0);
    await createChapter(b2, v2a, '第二章 来自深空的信号',
        '　　跃迁第七日，雷达捕捉到一段异常信号。\n\n'
        '　　苏晚将其接入主控台，波形在屏幕上起伏，规律得不像自然噪声。她反复回放，心跳渐渐加快——这是一段被调制过的序列，有人，或有什么东西，在深空里说话。\n\n'
        '　　"你确定？"副手老陈凑过来看。\n\n'
        '　　"确定。频率、间隔、重复周期，都不是自然来源。"她调出星图，标记信号方位，"而且……它在我们预定的航向上。"\n\n'
        '　　舰桥陷入沉默。四十二年的航程，才走完一周，前方却已有人等候。', 1);
    await createChapter(b2, v2a, '第三章 静默',
        '　　他们尝试回复，信号却再没出现。\n\n'
        '　　此后数日，苏晚每班都盯着那个方位，屏幕上只有宇宙微波背景的均匀底噪。老陈劝她也许是仪器误判，她没辩驳，只是把原始数据存进了独立日志。\n\n'
        '　　夜里她睡不着，飘到观测舱，望着舷外的星河。那么多人间的事，在光年之外都轻得像尘。可那段信号，却像有人在极远处点了一盏灯，亮了一下，又灭了。\n\n'
        '　　她不知道自己该希望它再亮，还是永远别再亮。', 2);

    final b3 = await createBook('旧时光书签', '林小夏');
    final v3a = await createVolume(b3, '第一卷', 0);
    await createChapter(b3, v3a, '第一章 转角的书店',
        '　　巷子转角那家书店，林小夏走了三年才注意到。\n\n'
        '　　门脸很小，招牌上写"旧时光"，字迹被雨洗得发淡。推门进去，铃铛响了一声。满屋子都是纸页的气味，暖而干燥。\n\n'
        '　　柜台后坐着个老人，戴老花镜，正在修补一本脱线的旧书。听见铃响，抬眼笑了笑："随便看。"\n\n'
        '　　小夏在书架间穿行，指尖划过一排排书脊。最里层有一格，放的不是书，是一只只玻璃罐，里头装着折好的纸鹤、干花、车票，还有一张泛黄的照片。\n\n'
        '　　"这些是什么？"她忍不住问。\n\n'
        '　　老人放下手中的针线："是别人寄存在这儿的东西。每个人总有些旧物，舍不得丢，又没处放。"\n\n'
        '　　小夏望着那些罐子，忽然想起自己背包里，也一直收着一张三年前的电影票根。', 0);

    await db.close();
    print('seeded: 3 books, 4 volumes, 8 chapters');
  });
}

int _countChars(String content) {
  var n = 0;
  for (final rune in content.runes) {
    final ch = String.fromCharCode(rune);
    if (ch.trim().isNotEmpty) n++;
  }
  return n;
}
