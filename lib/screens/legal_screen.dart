import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import '../widgets/common_widgets.dart';

typedef _Section = ({String heading, String body});

class _LegalScaffold extends StatelessWidget {
  const _LegalScaffold({
    required this.title,
    required this.updatedLabel,
    required this.sections,
  });
  final String title;
  final String updatedLabel;
  final List<_Section> sections;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SingleChildScrollView(
      child: ContentFrame(
        maxWidth: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              updatedLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            for (final section in sections) ...[
              Text(
                section.heading,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(section.body, style: const TextStyle(height: 1.6)),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    ),
  );
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) => _LegalScaffold(
    title: context.l10n.t('termsTitle'),
    updatedLabel: context.l10n.t('legalUpdatedAt'),
    sections: switch (appState.locale) {
      AppLocale.ja => const [
        (
          heading: '1. 適用',
          body:
              'この利用規約(以下「本規約」)は、Yorimichi Works(以下「運営者」)が提供する'
              '「tier表オンライン」(以下「本サービス」)の利用条件を定めるものです。'
              '本サービスを利用した時点で、本規約に同意したものとみなします。',
        ),
        (heading: '2. 運営者', body: '本サービスは個人開発者(屋号: Yorimichi Works)が運営しています。'),
        (
          heading: '3. アカウント',
          body:
              '本サービスは匿名認証、メールアドレス/パスワード、Googleアカウントでの利用に対応しています。'
              'メールアドレス/パスワードで登録した場合、メールアドレスの確認が完了するまで一部の機能'
              '(Tierの公開、コメント、いいね、フォロー、通報、プロフィール公開、画像アップロードなど)'
              'を制限することがあります。',
        ),
        (
          heading: '4. 禁止事項',
          body:
              '利用者は本サービスの利用にあたり、以下の行為を行ってはなりません。\n'
              '・法令または公序良俗に違反する行為\n'
              '・他者の著作権、肖像権、プライバシー、その他の権利を侵害する行為\n'
              '・誹謗中傷、差別的表現、なりすまし\n'
              '・スパム行為、本サービスの機能を利用した迷惑行為\n'
              '・不正アクセス、リバースエンジニアリング、サーバーへの過度な負荷を与える行為\n'
              '・その他、運営者が不適切と判断する行為',
        ),
        (
          heading: '5. 投稿コンテンツの取り扱い',
          body:
              '利用者が本サービスに投稿・アップロードした画像、テキスト、コメント等(以下「投稿コンテンツ」)の'
              '著作権その他の権利は、投稿した利用者に帰属します。ただし利用者は運営者に対し、本サービスの'
              '提供・表示、および検索エンジンやSNS等での共有プレビュー(OGP)表示・キャッシュ配信に必要な範囲で、'
              '投稿コンテンツを無償・非独占的に複製、表示、送信、キャッシュする権利を許諾するものとします。',
        ),
        (
          heading: '6. 権利侵害コンテンツの削除依頼',
          body:
              '第三者の権利を侵害する投稿コンテンツを発見した場合は、本サービス内の「お問い合わせ」フォーム'
              'から削除依頼・権利侵害の申告を行うことができます。運営者は内容を確認のうえ、必要と判断した'
              '場合に削除等の対応を行います。',
        ),
        (
          heading: '7. 免責事項',
          body:
              '本サービスは現状有姿で提供され、内容の正確性、完全性、有用性、特定目的への適合性、'
              '継続的な利用可能性についていかなる保証も行いません。本サービスの利用により生じた損害について、'
              '運営者は法令上許容される範囲で責任を負いません。',
        ),
        (
          heading: '8. サービスの変更・中断・終了',
          body:
              '運営者は利用者への事前の通知なく、本サービスの内容を変更し、または提供を中断・終了する'
              'ことがあります。これによって利用者に生じた損害について、運営者は責任を負いません。',
        ),
        (
          heading: '9. 規約の変更',
          body: '本規約は、運営者の判断により予告なく変更されることがあります。変更後の規約は本サービス上に掲載した時点から効力を生じます。',
        ),
        (
          heading: '10. 準拠法・裁判管轄',
          body:
              '本規約の解釈にあたっては日本法を準拠法とします。本サービスに関して紛争が生じた場合、運営者の所在地を管轄する裁判所を第一審の専属的合意管轄裁判所とします。',
        ),
      ],
      AppLocale.ko => const [
        (
          heading: '1. 적용',
          body:
              '본 이용약관(이하 "본 약관")은 Yorimichi Works(이하 "운영자")가 제공하는 '
              '"tier표 온라인"(이하 "본 서비스")의 이용 조건을 정합니다. 본 서비스를 이용하는 '
              '시점에 본 약관에 동의한 것으로 간주합니다.',
        ),
        (heading: '2. 운영자', body: '본 서비스는 개인 개발자(상호: Yorimichi Works)가 운영합니다.'),
        (
          heading: '3. 계정',
          body:
              '본 서비스는 익명 인증, 이메일/비밀번호, Google 계정 이용을 지원합니다. 이메일/비밀번호로 '
              '가입한 경우, 이메일 인증이 완료될 때까지 일부 기능(Tier 공개, 댓글, 좋아요, 팔로우, 신고, '
              '프로필 공개, 이미지 업로드 등)이 제한될 수 있습니다.',
        ),
        (
          heading: '4. 금지 행위',
          body:
              '이용자는 본 서비스 이용 시 다음 행위를 해서는 안 됩니다.\n'
              '・법령 또는 공서양속에 위반하는 행위\n'
              '・타인의 저작권, 초상권, 개인정보, 기타 권리를 침해하는 행위\n'
              '・비방, 차별적 표현, 사칭\n'
              '・스팸 행위, 본 서비스 기능을 악용한 방해 행위\n'
              '・부정 접근, 리버스 엔지니어링, 서버에 과도한 부하를 주는 행위\n'
              '・기타 운영자가 부적절하다고 판단하는 행위',
        ),
        (
          heading: '5. 게시 콘텐츠의 취급',
          body:
              '이용자가 본 서비스에 게시·업로드한 이미지, 텍스트, 댓글 등(이하 "게시 콘텐츠")의 저작권 '
              '기타 권리는 게시한 이용자에게 귀속됩니다. 다만 이용자는 운영자에게 본 서비스의 제공·표시, '
              '그리고 검색엔진이나 SNS 등의 공유 미리보기(OGP) 표시·캐시 배포에 필요한 범위에서 게시 '
              '콘텐츠를 무상·비독점적으로 복제, 표시, 전송, 캐시할 권리를 허락하는 것으로 합니다.',
        ),
        (
          heading: '6. 권리 침해 콘텐츠 삭제 요청',
          body:
              '제3자의 권리를 침해하는 게시 콘텐츠를 발견한 경우, 본 서비스 내 "문의하기" 양식을 통해 '
              '삭제 요청·권리 침해 신고를 할 수 있습니다. 운영자는 내용을 확인한 후 필요하다고 판단되면 '
              '삭제 등의 조치를 취합니다.',
        ),
        (
          heading: '7. 면책 조항',
          body:
              '본 서비스는 있는 그대로 제공되며, 내용의 정확성, 완전성, 유용성, 특정 목적 적합성, 지속적인 '
              '이용 가능성에 대해 어떠한 보증도 하지 않습니다. 본 서비스 이용으로 발생한 손해에 대해 '
              '운영자는 법령이 허용하는 범위에서 책임을 지지 않습니다.',
        ),
        (
          heading: '8. 서비스의 변경·중단·종료',
          body:
              '운영자는 이용자에게 사전 통지 없이 본 서비스의 내용을 변경하거나 제공을 중단·종료할 수 '
              '있습니다. 이로 인해 이용자에게 발생한 손해에 대해 운영자는 책임을 지지 않습니다.',
        ),
        (
          heading: '9. 약관의 변경',
          body:
              '본 약관은 운영자의 판단에 따라 예고 없이 변경될 수 있습니다. 변경된 약관은 본 서비스에 게재된 시점부터 효력이 발생합니다.',
        ),
        (
          heading: '10. 준거법·관할 법원',
          body:
              '본 약관의 해석에는 일본법을 준거법으로 합니다. 본 서비스와 관련하여 분쟁이 발생한 경우, 운영자 소재지를 관할하는 법원을 1심 전속 합의 관할 법원으로 합니다.',
        ),
      ],
      AppLocale.zhTw => const [
        (
          heading: '1. 適用範圍',
          body:
              '本服務條款（以下稱「本條款」）規範使用者使用由 Yorimichi Works（以下稱「營運者」）'
              '提供之「Tier Online」（以下稱「本服務」）時的條件。使用本服務即視為同意本條款。',
        ),
        (heading: '2. 營運者', body: '本服務由個人開發者以 Yorimichi Works 名義營運。'),
        (
          heading: '3. 帳號',
          body:
              '本服務支援匿名驗證、電子郵件／密碼帳號及 Google 登入。使用電子郵件／密碼註冊時，'
              '在完成電子郵件驗證前，部分功能（發布 Tier、留言、按讚、追蹤、檢舉、公開個人檔案、上傳圖片等）可能受到限制。',
        ),
        (
          heading: '4. 禁止行為',
          body:
              '使用者不得從事下列行為：\n'
              '・違反法令、公序良俗之行為\n'
              '・侵害他人著作權、肖像權、隱私權或其他權利之行為\n'
              '・誹謗、歧視、冒充他人\n'
              '・散播垃圾訊息或濫用本服務功能造成他人困擾\n'
              '・未經授權存取、逆向工程或對伺服器造成過度負載\n'
              '・其他經營運者判定為不當之行為',
        ),
        (
          heading: '5. 使用者投稿內容',
          body:
              '使用者於本服務投稿或上傳之圖片、文字、留言等內容（以下稱「投稿內容」），其著作權及其他權利仍歸使用者所有。'
              '但使用者同意授予營運者免費、非專屬之權利，得於提供及顯示本服務、搜尋引擎或社群平台分享預覽（OGP）及快取所必要的範圍內，'
              '重製、顯示、傳輸及快取投稿內容。',
        ),
        (
          heading: '6. 權利侵害內容之移除要求',
          body:
              '如發現侵害第三方權利之投稿內容，可透過本服務內的「聯絡我們」表單提出移除要求或權利侵害檢舉。'
              '營運者將審查內容，並於認定有必要時採取移除等措施。',
        ),
        (
          heading: '7. 免責聲明',
          body:
              '本服務依現狀提供，不保證內容之正確性、完整性、實用性、特定用途適用性或持續可用性。'
              '除法律另有規定外，營運者不對使用本服務所生之損害負責。',
        ),
        (
          heading: '8. 服務變更、暫停與終止',
          body: '營運者得不經事前通知變更、暫停或終止本服務。除法律另有規定外，營運者不對因此造成之損害負責。',
        ),
        (heading: '9. 條款變更', body: '營運者得不經事前通知修改本條款。修改後之條款自公布於本服務時起生效。'),
        (
          heading: '10. 準據法與管轄法院',
          body: '本條款以日本法律為準據法。因本服務所生之爭議，以營運者所在地之管轄法院為第一審專屬合意管轄法院。',
        ),
      ],
      AppLocale.ptBr => const [
        (
          heading: '1. Aplicação',
          body:
              'Estes Termos de Serviço (“Termos”) regem o uso do “Tier Online” (“Serviço”), oferecido pela Yorimichi Works (“operador”). Ao usar o Serviço, você concorda com estes Termos.',
        ),
        (
          heading: '2. Operador',
          body:
              'O Serviço é operado por um desenvolvedor individual sob o nome Yorimichi Works.',
        ),
        (
          heading: '3. Contas',
          body:
              'O Serviço permite autenticação anônima, contas por e-mail e senha e login do Google. Em contas por e-mail e senha, alguns recursos — como publicar Tiers, comentar, curtir, seguir, denunciar, exibir perfil público e enviar imagens — podem ficar limitados até a confirmação do e-mail.',
        ),
        (
          heading: '4. Condutas proibidas',
          body:
              'Ao usar o Serviço, você não pode:\n'
              '・Violar leis aplicáveis, a ordem pública ou os bons costumes\n'
              '・Violar direitos autorais, de imagem, privacidade ou outros direitos de terceiros\n'
              '・Assediar, difamar, discriminar ou se passar por outra pessoa\n'
              '・Enviar spam ou abusar dos recursos do Serviço\n'
              '・Tentar acesso não autorizado, engenharia reversa ou impor carga excessiva aos servidores\n'
              '・Praticar qualquer outra conduta que o operador considere inadequada',
        ),
        (
          heading: '5. Conteúdo enviado',
          body:
              'Os direitos autorais e demais direitos sobre imagens, textos, comentários e outros conteúdos enviados ao Serviço permanecem com o usuário. Você concede ao operador uma licença gratuita e não exclusiva para reproduzir, exibir, transmitir e armazenar em cache esse conteúdo, na medida necessária para operar e exibir o Serviço, gerar prévias de compartilhamento (OGP) e permitir cache por mecanismos de busca.',
        ),
        (
          heading: '6. Remoção de conteúdo que viola direitos',
          body:
              'Caso encontre conteúdo que viole direitos de terceiros, solicite a remoção ou denuncie a violação pelo formulário “Contato”. O operador analisará o relato e tomará as medidas necessárias, inclusive a remoção.',
        ),
        (
          heading: '7. Isenção de responsabilidade',
          body:
              'O Serviço é fornecido no estado em que se encontra, sem garantia de precisão, integridade, utilidade, adequação a uma finalidade específica ou disponibilidade contínua. O operador não se responsabiliza por danos decorrentes do uso, salvo quando exigido por lei.',
        ),
        (
          heading: '8. Alteração, suspensão e encerramento',
          body:
              'O operador pode alterar, suspender ou encerrar o Serviço sem aviso prévio e não se responsabiliza por danos decorrentes dessas medidas, salvo quando exigido por lei.',
        ),
        (
          heading: '9. Alterações destes Termos',
          body:
              'Estes Termos podem ser alterados sem aviso prévio. A nova versão entra em vigor quando publicada no Serviço.',
        ),
        (
          heading: '10. Lei aplicável e foro',
          body:
              'Estes Termos são regidos pelas leis do Japão. Qualquer disputa relacionada ao Serviço fica sujeita à jurisdição exclusiva, em primeira instância, do tribunal competente da localização do operador.',
        ),
      ],
      AppLocale.en => const [
        (
          heading: '1. Scope',
          body:
              'These Terms of Service ("Terms") govern your use of "Tier Online" '
              '(the "Service"), provided by Yorimichi Works ("we", "us", "the operator"). '
              'By using the Service, you agree to these Terms.',
        ),
        (
          heading: '2. Operator',
          body:
              'The Service is operated by an individual developer under the name Yorimichi Works.',
        ),
        (
          heading: '3. Accounts',
          body:
              'The Service supports anonymous authentication, email/password accounts, and Google '
              'sign-in. For email/password accounts, some features (publishing a tier list, comments, '
              'likes, follows, reports, public profiles, image uploads) may be restricted until email '
              'verification is complete.',
        ),
        (
          heading: '4. Prohibited Conduct',
          body:
              'You must not, while using the Service:\n'
              '• Violate any applicable law or public order and morals\n'
              '• Infringe the copyright, likeness rights, privacy, or other rights of others\n'
              '• Harass, defame, or impersonate others\n'
              '• Spam or otherwise abuse the Service\'s features\n'
              '• Attempt unauthorized access, reverse engineering, or place excessive load on servers\n'
              '• Engage in any other conduct we deem inappropriate',
        ),
        (
          heading: '5. Handling of Submitted Content',
          body:
              'Copyright and other rights in images, text, comments, and other content you submit or '
              'upload to the Service ("Submitted Content") remain with you. However, you grant us a '
              'royalty-free, non-exclusive license to reproduce, display, transmit, and cache Submitted '
              'Content to the extent necessary to operate and display the Service, and to generate share '
              'previews (OGP) and search-engine caching.',
        ),
        (
          heading: '6. Requesting Removal of Infringing Content',
          body:
              'If you discover Submitted Content that infringes a third party\'s rights, you may request '
              'removal or report the infringement via the "Contact" form in the Service. We will review '
              'the report and take action, such as removal, where we determine it is necessary.',
        ),
        (
          heading: '7. Disclaimer',
          body:
              'The Service is provided "as is" without any warranty as to accuracy, completeness, '
              'usefulness, fitness for a particular purpose, or continued availability. We are not '
              'liable for damages arising from use of the Service, except as required by law.',
        ),
        (
          heading: '8. Changes, Suspension, and Termination',
          body:
              'We may change, suspend, or discontinue the Service at any time without prior notice. '
              'We are not liable for any damages this causes you.',
        ),
        (
          heading: '9. Changes to These Terms',
          body:
              'We may revise these Terms at any time without prior notice. Revised Terms take effect once posted within the Service.',
        ),
        (
          heading: '10. Governing Law and Jurisdiction',
          body:
              'These Terms are governed by the laws of Japan. Any dispute relating to the Service is subject to the exclusive jurisdiction of the court having jurisdiction over the operator\'s location as the court of first instance.',
        ),
      ],
    },
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) => _LegalScaffold(
    title: context.l10n.t('privacyTitle'),
    updatedLabel: context.l10n.t('legalUpdatedAt'),
    sections: switch (appState.locale) {
      AppLocale.ja => const [
        (
          heading: '1. 取得する情報',
          body:
              '本サービスは以下の情報を取得します。\n'
              '・Firebase Authenticationにより取得する情報: メールアドレス、ユーザーID、'
              '(Googleログイン利用時)氏名・プロフィール画像URL、匿名利用時の匿名ID\n'
              '・利用者が投稿する情報: アップロードした画像、Tierの並び順(回答内容)、コメント'
              '(「語る」機能)、いいね、通報・お問い合わせの内容\n'
              '・自動的に取得される情報: Google AdMobによる広告配信のための端末情報・広告識別子・'
              'Cookie等、サービス利用状況に関するログ情報',
        ),
        (
          heading: '2. 利用目的',
          body:
              '取得した情報は、本サービスの提供・維持、不正利用の防止、投稿内容のモデレーション'
              '(不適切な言葉の自動検知等)、広告の配信、お問い合わせへの対応、サービスの改善のために'
              '利用します。',
        ),
        (
          heading: '3. 第三者への提供・業務委託',
          body:
              '本サービスは以下の外部サービスを利用しており、必要な範囲で情報が各サービスに送信されます。\n'
              '・Google Firebase(Authentication、Cloud Firestore、Cloud Functions、Hosting、'
              'Cloud Storage)\n'
              '・Google AdMob(広告配信)\n'
              '・Google Sign-In(Googleアカウントでのログイン)\n'
              '・Google Custom Search API(画像検索機能の利用時)\n'
              '各サービスのプライバシーポリシーもあわせてご確認ください。',
        ),
        (
          heading: '4. Cookie・広告識別子について',
          body:
              '本サービスはGoogle AdMobによる広告を表示しており、パーソナライズ広告の配信のために'
              'Cookieや端末の広告識別子を使用することがあります。これらはブラウザの設定や端末の'
              '「広告のパーソナライズ」設定から無効化できます。',
        ),
        (
          heading: '5. データの保存期間・削除',
          body:
              '投稿コンテンツやアカウント情報は、利用者本人が削除操作を行うことで削除されます。'
              'アカウントの削除やデータの削除を希望する場合は、「お問い合わせ」フォームから'
              'ご連絡ください。内容確認のうえ、必要な対応を行います。',
        ),
        (
          heading: '6. 未成年の利用について',
          body: '本サービスは明確な年齢制限を設けていませんが、未成年の方は保護者の同意のもとでご利用ください。',
        ),
        (
          heading: '7. お問い合わせ窓口',
          body:
              '個人情報の取り扱いに関するお問い合わせ、削除依頼、権利侵害の申告は、本サービス内の「お問い合わせ」フォームから受け付けています。',
        ),
        (
          heading: '8. 本ポリシーの改定',
          body: 'このプライバシーポリシーは、法令の変更や本サービスの内容変更に伴い、予告なく改定されることがあります。',
        ),
      ],
      AppLocale.ko => const [
        (
          heading: '1. 수집하는 정보',
          body:
              '본 서비스는 다음 정보를 수집합니다.\n'
              '・Firebase Authentication을 통해 수집하는 정보: 이메일 주소, 사용자 ID, '
              '(Google 로그인 이용 시) 이름·프로필 이미지 URL, 익명 이용 시 익명 ID\n'
              '・이용자가 게시하는 정보: 업로드한 이미지, Tier 배치(응답 내용), 댓글'
              '("이야기하기" 기능), 좋아요, 신고·문의 내용\n'
              '・자동으로 수집되는 정보: Google AdMob 광고 게재를 위한 기기 정보·광고 식별자·'
              '쿠키 등, 서비스 이용 현황에 관한 로그 정보',
        ),
        (
          heading: '2. 이용 목적',
          body:
              '수집한 정보는 본 서비스의 제공·유지, 부정 이용 방지, 게시 내용 모더레이션'
              '(부적절한 표현 자동 감지 등), 광고 게재, 문의 대응, 서비스 개선을 위해 이용합니다.',
        ),
        (
          heading: '3. 제3자 제공·위탁',
          body:
              '본 서비스는 다음 외부 서비스를 이용하고 있으며, 필요한 범위에서 정보가 각 서비스로 '
              '전송됩니다.\n'
              '・Google Firebase(Authentication, Cloud Firestore, Cloud Functions, Hosting, '
              'Cloud Storage)\n'
              '・Google AdMob(광고 게재)\n'
              '・Google Sign-In(Google 계정 로그인)\n'
              '・Google Custom Search API(이미지 검색 기능 이용 시)\n'
              '각 서비스의 개인정보처리방침도 함께 확인해 주세요.',
        ),
        (
          heading: '4. 쿠키·광고 식별자에 대하여',
          body:
              '본 서비스는 Google AdMob을 통한 광고를 게재하며, 맞춤형 광고 제공을 위해 쿠키나 '
              '기기의 광고 식별자를 사용할 수 있습니다. 브라우저 설정이나 기기의 "광고 맞춤 설정"에서 '
              '비활성화할 수 있습니다.',
        ),
        (
          heading: '5. 데이터 보관 기간·삭제',
          body:
              '게시 콘텐츠 및 계정 정보는 이용자 본인이 삭제 조작을 하면 삭제됩니다. 계정 삭제나 '
              '데이터 삭제를 원하시는 경우 "문의하기" 양식으로 연락해 주세요. 내용 확인 후 필요한 '
              '조치를 취합니다.',
        ),
        (
          heading: '6. 미성년자의 이용에 대하여',
          body: '본 서비스는 명확한 연령 제한을 두고 있지 않으나, 미성년자는 보호자의 동의 하에 이용해 주세요.',
        ),
        (
          heading: '7. 문의 창구',
          body:
              '개인정보 취급에 관한 문의, 삭제 요청, 권리 침해 신고는 본 서비스 내 "문의하기" 양식으로 접수하고 있습니다.',
        ),
        (
          heading: '8. 본 방침의 개정',
          body: '이 개인정보처리방침은 법령 변경이나 본 서비스 내용 변경에 따라 예고 없이 개정될 수 있습니다.',
        ),
      ],
      AppLocale.zhTw => const [
        (
          heading: '1. 蒐集的資訊',
          body:
              '本服務會蒐集下列資訊：\n'
              '・透過 Firebase Authentication 取得的資訊：電子郵件地址、使用者 ID、使用 Google 登入時的姓名與個人圖片網址，以及匿名使用時的匿名 ID\n'
              '・使用者投稿的資訊：上傳圖片、Tier 排列（回答內容）、留言（「討論」功能）、按讚、檢舉與聯絡內容\n'
              '・自動取得的資訊：Google AdMob 廣告投放所需的裝置資訊、廣告識別碼、Cookie，以及服務使用情形相關記錄',
        ),
        (
          heading: '2. 使用目的',
          body: '蒐集的資訊將用於提供與維護本服務、防止濫用、投稿內容審核（例如自動偵測不當文字）、廣告投放、回覆詢問及改善服務。',
        ),
        (
          heading: '3. 第三方服務與委外處理',
          body:
              '本服務使用下列外部服務，必要資訊可能在所需範圍內傳送至各服務：\n'
              '・Google Firebase（Authentication、Cloud Firestore、Cloud Functions、Hosting、Cloud Storage）\n'
              '・Google AdMob（廣告投放）\n'
              '・Google Sign-In（Google 帳號登入）\n'
              '・Google Custom Search API、Openverse 與 Wikipedia（圖片搜尋）\n'
              '亦請參閱各服務的隱私權政策。',
        ),
        (
          heading: '4. Cookie 與廣告識別碼',
          body:
              '本服務會顯示 Google AdMob 廣告，可能使用 Cookie 或裝置廣告識別碼投放個人化廣告。'
              '你可以透過瀏覽器或裝置的廣告個人化設定停用相關功能。',
        ),
        (
          heading: '5. 資料保存期間與刪除',
          body:
              '投稿內容與帳號資訊可由使用者本人執行刪除操作。若希望刪除帳號或資料，亦可透過「聯絡我們」表單提出要求；'
              '營運者確認內容後將採取必要措施。',
        ),
        (heading: '6. 未成年人使用', body: '本服務未設定明確年齡限制，但未成年人應在監護人同意下使用。'),
        (heading: '7. 聯絡窗口', body: '有關個人資料處理、刪除要求或權利侵害之申訴，可透過本服務內的「聯絡我們」表單提出。'),
        (heading: '8. 隱私權政策修訂', body: '本政策可能因法令或服務內容變更而不經事前通知修訂。'),
      ],
      AppLocale.ptBr => const [
        (
          heading: '1. Informações coletadas',
          body:
              'O Serviço coleta:\n'
              '・Dados do Firebase Authentication: e-mail, ID do usuário, nome e URL da foto no login do Google e ID anônimo no uso anônimo\n'
              '・Dados enviados pelo usuário: imagens, ordenação da Tier, comentários, curtidas, denúncias e mensagens de contato\n'
              '・Dados automáticos: informações do dispositivo, identificador de publicidade, cookies e registros de uso necessários ao Google AdMob e à operação do Serviço',
        ),
        (
          heading: '2. Finalidades',
          body:
              'Usamos os dados para oferecer e manter o Serviço, impedir abusos, moderar conteúdo, exibir anúncios, responder solicitações e melhorar o Serviço.',
        ),
        (
          heading: '3. Serviços de terceiros',
          body:
              'O Serviço utiliza provedores externos e pode enviar a eles os dados necessários:\n'
              '・Google Firebase (Authentication, Cloud Firestore, Cloud Functions, Hosting e Cloud Storage)\n'
              '・Google AdMob (publicidade)\n'
              '・Google Sign-In (login)\n'
              '・Google Custom Search API, Openverse e Wikipedia (busca de imagens)\n'
              'Consulte também as políticas de privacidade desses serviços.',
        ),
        (
          heading: '4. Cookies e identificadores de publicidade',
          body:
              'O Serviço exibe anúncios do Google AdMob e pode usar cookies ou o identificador de publicidade do dispositivo para anúncios personalizados. Você pode desativar a personalização nas configurações do navegador ou do dispositivo.',
        ),
        (
          heading: '5. Retenção e exclusão de dados',
          body:
              'O usuário pode excluir seu conteúdo e seus dados de conta pelos recursos disponíveis. Também é possível solicitar exclusão pelo formulário “Contato”; o operador analisará a solicitação e tomará as medidas necessárias.',
        ),
        (
          heading: '6. Uso por menores de idade',
          body:
              'O Serviço não estabelece uma idade mínima específica, mas menores devem usá-lo com autorização de seu responsável.',
        ),
        (
          heading: '7. Contato',
          body:
              'Dúvidas sobre dados pessoais, pedidos de exclusão e denúncias de violação de direitos podem ser enviados pelo formulário “Contato” do Serviço.',
        ),
        (
          heading: '8. Alterações desta Política',
          body:
              'Esta Política pode ser alterada sem aviso prévio em razão de mudanças legais ou no Serviço.',
        ),
      ],
      AppLocale.en => const [
        (
          heading: '1. Information We Collect',
          body:
              'The Service collects the following information:\n'
              '• Via Firebase Authentication: email address, user ID, (when using Google sign-in) '
              'name and profile photo URL, anonymous ID for anonymous use\n'
              '• Information you submit: uploaded images, tier placements (your rankings), comments '
              '(the "Talk" feature), likes, and the content of reports or contact submissions\n'
              '• Automatically collected information: device information, advertising identifiers, and '
              'cookies used by Google AdMob for ad delivery, and usage logs',
        ),
        (
          heading: '2. Purpose of Use',
          body:
              'We use collected information to provide and maintain the Service, prevent abuse, '
              'moderate submitted content (e.g. automated detection of inappropriate language), serve '
              'ads, respond to inquiries, and improve the Service.',
        ),
        (
          heading: '3. Third-Party Sharing and Subprocessors',
          body:
              'The Service relies on the following external services, to which relevant information is '
              'sent as needed:\n'
              '• Google Firebase (Authentication, Cloud Firestore, Cloud Functions, Hosting, Cloud '
              'Storage)\n'
              '• Google AdMob (ad delivery)\n'
              '• Google Sign-In (Google account login)\n'
              '• Google Custom Search API (when using the image search feature)\n'
              'Please also review each service\'s privacy policy for how it handles data.',
        ),
        (
          heading: '4. Cookies and Advertising Identifiers',
          body:
              'The Service displays ads via Google AdMob, which may use cookies or your device\'s '
              'advertising identifier to deliver personalized ads. You can opt out via your browser '
              'settings or your device\'s ad personalization settings.',
        ),
        (
          heading: '5. Data Retention and Deletion',
          body:
              'Submitted content and account data are removed when you delete them yourself. If you '
              'would like your account or data deleted, please contact us via the "Contact" form. We '
              'will review your request and take appropriate action.',
        ),
        (
          heading: '6. Use by Minors',
          body:
              'The Service does not enforce a specific age restriction, but minors should use it with a parent or guardian\'s consent.',
        ),
        (
          heading: '7. Contact',
          body:
              'Inquiries about how we handle personal data, deletion requests, and reports of rights infringement are accepted via the "Contact" form within the Service.',
        ),
        (
          heading: '8. Changes to This Policy',
          body:
              'We may revise this Privacy Policy at any time, without prior notice, to reflect changes in law or in the Service.',
        ),
      ],
    },
  );
}
