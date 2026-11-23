import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/operations/presentation/operations_widgets.dart'
    show confirmDelete;
import '../theme/app_theme.dart';

// Liste satırlarına ortak düzenle / sil hareketleri: uzun basışta "Düzenle /
// Sil" alt sayfası ve sola kaydırarak silme. Her iki yol da silmeden önce
// mevcut silme onayını (`confirmDelete`) sorar.

/// Silme başarısız oldu ve kullanıcı zaten bilgilendirildi. [SwipeToDelete]
/// bu hatayı günlüğe yazmadan satırı geri getirir.
class ItemDeleteFailed implements Exception {
  const ItemDeleteFailed();

  @override
  String toString() => 'ItemDeleteFailed';
}

enum _ItemChoice { edit, delete }

/// Satıra uzun basınca "Düzenle / Sil" alt sayfasını açar. "Sil" seçilirse
/// önce onay sorulur; yalnızca onaylanırsa [onDelete] bir kez çağrılır.
///
/// [child] içindeki kısa dokunuşlar (işaretleme, düzenleme formu) aynen çalışır.
class ItemActions extends StatelessWidget {
  const ItemActions({
    super.key,
    required this.title,
    required this.onEdit,
    required this.onDelete,
    required this.child,
    this.confirmTitle,
    this.confirmMessage,
  });

  /// Alt sayfa başlığı ve varsayılan onay metni için kaydın adı.
  final String title;
  final VoidCallback onEdit;

  /// Onaydan sonra çağrılır; onayı bu bileşen sorar.
  final VoidCallback onDelete;
  final Widget child;

  /// Verilmezse "Silinsin mi?".
  final String? confirmTitle;

  /// Verilmezse `"[title]" kalıcı olarak silinecek.`
  final String? confirmMessage;

  Future<void> _open(BuildContext context) async {
    final choice = await showModalBottomSheet<_ItemChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      builder: (_) => _ItemActionsSheet(title: title),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _ItemChoice.edit:
        onEdit();
      case _ItemChoice.delete:
        final confirmed = await confirmDelete(
          context,
          title: confirmTitle ?? 'Silinsin mi?',
          message: confirmMessage ?? '"$title" kalıcı olarak silinecek.',
        );
        // Onay açıkken satır listeden kalkmış olabilir; o zaman bağlamı
        // olmayan satır için işlem yapılmaz.
        if (confirmed && context.mounted) onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _open(context),
      child: child,
    );
  }
}

class _ItemActionsSheet extends StatelessWidget {
  const _ItemActionsSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading:
                  Icon(Icons.edit_outlined, color: AppColors.textSecondary),
              title: const Text('Düzenle'),
              onTap: () => Navigator.of(context).pop(_ItemChoice.edit),
            ),
            ListTile(
              leading:
                  Icon(Icons.delete_outline_outlined, color: AppColors.danger),
              title: Text('Sil', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.of(context).pop(_ItemChoice.delete),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Satırı sola kaydırınca silme onayı sorar. "Vazgeç"te satır geri gelir.
///
/// [onDelete] onaydan sonra çağrılır. Hata fırlatırsa (ya da [ItemDeleteFailed]
/// ile bitirirse) satır geri gelir; başarıyla dönerse satır, veri kaynağı onu
/// listeden kaldırana dek gizli kalır.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.itemKey,
    required this.confirmTitle,
    required this.confirmMessage,
    required this.onDelete,
    required this.child,
    this.borderRadius,
  });

  /// Kayıt başına benzersiz anahtar (örn. `ValueKey('swipe-task-$id')`).
  final Key itemKey;
  final String confirmTitle;
  final String confirmMessage;
  final FutureOr<void> Function() onDelete;
  final Widget child;

  /// Kart gibi yuvarlak köşeli satırlarda kırmızı zemin de yuvarlatılır.
  final BorderRadius? borderRadius;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  /// Silinen kaydın anahtarı. Liste kayınca bu durum bir sonraki satıra
  /// geçmesin diye bool yerine anahtar tutulur.
  Key? _removedKey;

  Future<bool> _confirmDismiss(DismissDirection direction) async {
    // Onay penceresi açıkken satırın State'i başka kayda bağlanabilir (liste
    // kayar); `widget` o zaman komşunun yapılandırmasıdır. Silinecek kaydın
    // her şeyi onay beklenmeden önce yakalanır.
    final key = widget.itemKey;
    final onDelete = widget.onDelete;
    final confirmed = await confirmDelete(
      context,
      title: widget.confirmTitle,
      message: widget.confirmMessage,
    );
    if (!confirmed || !mounted) return false;
    try {
      await onDelete();
    } on ItemDeleteFailed {
      return false;
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'item_actions',
          context: ErrorDescription('while deleting a swiped item'),
        ),
      );
      return false;
    }
    if (mounted) setState(() => _removedKey = key);
    // Satırı Dismissible kaldırmaz: sağlayıcı yenilenene dek gizli tutulur.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_removedKey == widget.itemKey) return const SizedBox.shrink();

    final radius = widget.borderRadius;
    final dismissible = Dismissible(
      key: widget.itemKey,
      direction: DismissDirection.endToStart,
      confirmDismiss: _confirmDismiss,
      background: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: radius,
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Icon(
              Icons.delete_outline_outlined,
              color: AppColors.onAccent,
              semanticLabel: 'Sil',
            ),
          ),
        ),
      ),
      child: widget.child,
    );
    if (radius == null) return dismissible;
    return ClipRRect(borderRadius: radius, child: dismissible);
  }
}

/// [ItemActions] ve [SwipeToDelete]'in birlikte kullanımı: uzun basış menüsü
/// ve sola kaydırma, aynı düzenle / sil eylemlerine bağlanır.
class ItemRowActions extends StatelessWidget {
  const ItemRowActions({
    super.key,
    required this.itemKey,
    required this.title,
    required this.confirmTitle,
    required this.confirmMessage,
    required this.onEdit,
    required this.onDelete,
    required this.child,
    this.borderRadius,
  });

  final Key itemKey;
  final String title;
  final String confirmTitle;
  final String confirmMessage;
  final VoidCallback onEdit;

  /// Onay sorulmadan siler; başarıyla silindiyse `true` döner. Onayı bu
  /// bileşen sorar, hatayı kullanıcıya [onDelete] bildirir.
  final Future<bool> Function() onDelete;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return SwipeToDelete(
      itemKey: itemKey,
      confirmTitle: confirmTitle,
      confirmMessage: confirmMessage,
      borderRadius: borderRadius,
      onDelete: () async {
        if (!await onDelete()) throw const ItemDeleteFailed();
      },
      child: ItemActions(
        title: title,
        confirmTitle: confirmTitle,
        confirmMessage: confirmMessage,
        onEdit: onEdit,
        onDelete: () => unawaited(onDelete()),
        child: child,
      ),
    );
  }
}
