import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import 'common/dialogs.dart';
import 'widgets/toast.dart';

/// 登录弹窗（FR-12）：手机号/邮箱注册登录。
///
/// MVP 无服务端：本地模拟账号（仅记录登录标识并开启同步开关），
/// 接入真实服务端时替换 [MockAuthRepository]。
Future<void> showLoginDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const DraggableDialog(child: LoginDialog()),
  );
}

class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _idCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _register = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Text('账号登录'),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('登录')),
            ButtonSegment(value: true, label: Text('注册')),
          ],
          selected: {_register},
          onSelectionChanged: (s) => setState(() => _register = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _idCtrl,
          decoration: const InputDecoration(
              labelText: '手机号 / 邮箱',
              prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtrl,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: '密码 / 验证码',
              prefixIcon: Icon(Icons.lock_outline)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submit,
            child: Text(_register ? '注册并登录' : '登录'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '说明：MVP 版本为本地模拟账号；登录后开启云同步开关，'
          '断网可写、联网自动增量同步，冲突绝不静默覆盖。',
          style: TextStyle(fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ]),
      ),
    );
  }

  Future<void> _submit() async {
    final id = _idCtrl.text.trim();
    if (id.length < 5 || _codeCtrl.text.isEmpty) {
      setState(() => _error = '请输入有效的账号与密码/验证码');
      return;
    }
    await context.read<SettingsController>().setSyncEnabled(true);
    if (mounted) {
      showToast(context, '${_register ? '注册' : '登录'}成功：$id（本地模拟），云同步已开启');
      Navigator.pop(context);
    }
  }
}
