# App Leopardo

App das Impressoras Leopardo para Android (e iOS) feito em Flutter. Imprime em impressoras térmicas portáteis via Bluetooth Low Energy (BLE):

- **PDF ou imagem**: escolhidos no celular ou recebidos pelo "Compartilhar › Leopardo" (WhatsApp, Galeria, Arquivos).
- **Texto e recibo**: texto livre ou recibo com itens, total, forma de pagamento e a logo da loja.
- **Cobrança PIX**: gera o QR Code do PIX (padrão do Banco Central) com ou sem valor e imprime. Também copia o "PIX copia e cola" para enviar ao cliente pelo WhatsApp.
- **Impressora do sistema Android**: depois de ativar em Configurações › Impressão › Leopardo, as impressoras aparecem na tela "Imprimir" de qualquer app (PDF, Chrome, Galeria, documentos).
- **Texto compartilhado**: "Compartilhar › Leopardo" em uma mensagem de texto (ex.: pedido no WhatsApp) abre o texto pronto para imprimir.
- **Bluetooth clássico e USB**: além de BLE, imprime em impressoras Bluetooth comuns (pareadas no Android) e por cabo USB (OTG).
- **Comandos da impressora**: tom (claro/normal/escuro), avanço de papel e código de barras Code 128 no recibo.
- **Controle de fluxo**: comando de status (DLE EOT) ao final, atraso entre pacotes (0 a 1000 ms) e espera antes de desconectar (0 a 30 s).
- **Boleto em 80 mm**: lê um boleto em PDF A4 (texto ou imagem) e refaz o layout deitado na bobina, com código de barras no tamanho oficial e QR PIX quando houver.
- **Integração com sistemas** (ERPs, PDVs, sites e apps): veja a seção abaixo.
- Página de teste, reimpressão das últimas impressões, papel de 58 mm ou 80 mm e reconexão automática à última impressora.

Tudo é impresso como imagem (comando ESC/POS `GS v 0`). Isso garante acentuação, logo e QR Code de qualquer tamanho, inclusive o do PIX, sem o limite de 254 caracteres do QR nativo.

---

## Integração com outros sistemas

Qualquer app Android ou página web pode mandar imprimir pela impressora conectada no app Leopardo.

**Por link (sites, WhatsApp Web, sistemas web):**

```
leopardo://print?text=Pedido%20123%0ACliente%3A%20Maria
leopardo://print?base64=G0AbYQFPbOEhChtkAw==        (bytes ESC/POS em Base64)
```

Exemplo em JavaScript:

```js
const texto = "Pedido 123\nCliente: Maria\nTotal: R$ 48,90";
window.location.href = "leopardo://print?text=" + encodeURIComponent(texto);
```

**Por Intent (apps Android nativos, Kotlin/Java):**

```kotlin
val i = Intent("br.com.leopardo.PRINT")
i.setPackage("br.com.leopardo.leopardo_app")
i.putExtra("text", "Pedido 123\nTotal: R$ 48,90")   // ou:
// i.putExtra("bytes", escposBytes)                  // ByteArray com comandos ESC/POS
// i.putExtra("base64", "G0AbYQFP...")
startActivity(i)
```

- `text`: impresso como imagem, com acentos e no tom configurado no app.
- `bytes` / `base64`: comandos ESC/POS enviados sem alteração (corte, gaveta, código de barras nativo etc.).
- O app usa a impressora que estiver conectada (ou reconecta à última). Se não houver nenhuma, abre a tela de conexão.

## Como gerar o APK sem instalar nada (GitHub Actions)

1. Crie uma conta em [github.com](https://github.com) (se ainda não tiver).
2. Crie um repositório novo, por exemplo `leopardo-app` (pode ser **privado**).
3. Na página do repositório, clique em **Add file › Upload files**, arraste **todo o conteúdo** desta pasta (incluindo a pasta oculta `.github`) e clique em **Commit changes**.
   - Se o navegador não mostrar a pasta `.github`, use o GitHub Desktop ou o comando `git` (abaixo).
4. Abra a aba **Actions**. A automação **Gerar APK** começa sozinha e leva de 5 a 10 minutos.
5. Quando ficar verde, clique na execução e baixe **leopardo-app-apk** em *Artifacts*. Dentro do .zip está o `leopardo-app.apk`.
6. Copie o APK para o celular Android e abra. O Android vai pedir para permitir "instalar apps desta fonte".

Com git:

```bash
git init
git add .
git commit -m "App Leopardo v1"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/leopardo-app.git
git push -u origin main
```

Se a automação falhar, abra a execução, copie a mensagem de erro do passo que ficou vermelho e envie para o Claude corrigir.

## Como compilar no computador

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install) **3.24.5** (a mesma versão usada na automação) e Android Studio com o Android SDK.

```bash
flutter create --platforms=android,ios --org br.com.leopardo --project-name leopardo_app .
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release
```

O APK fica em `build/app/outputs/flutter-apk/app-release.apk`.

O primeiro comando completa as pastas `android/` e `ios/` com os arquivos padrão do Flutter, **sem sobrescrever** o `AndroidManifest.xml` deste projeto (que já tem as permissões de Bluetooth e o "Compartilhar › Leopardo").

## Testes com a impressora (checklist)

1. Ligue a impressora, abra o app e vá em **Impressoras**. Ela deve aparecer na lista (impressoras com "Leopardo" no nome aparecem primeiro).
2. Conecte e toque em **Imprimir teste** na tela inicial. Confira acentos, QR Code e largura.
3. Se a impressão sair cortada ou estreita, ajuste o papel (58 mm / 80 mm) em **Ajustes**.
4. Em **Ajustes**, preencha loja, logo e chave PIX. Imprima um recibo e uma cobrança PIX e leia o QR com o app de um banco.
5. No WhatsApp, abra um PDF, toque em **Compartilhar** e escolha **Leopardo**.

Se a impressora conectar mas não imprimir, provavelmente ela usa outro serviço BLE. Anote o modelo e os serviços dela (o app **nRF Connect** mostra) e ajuste a lista `_preferredServices` em `lib/services/printer_service.dart`.

## Publicar na Google Play

O APK gerado é assinado com a chave de depuração do Flutter: serve para testes e distribuição direta, mas **não** para a Play Store. Para publicar:

1. Crie uma chave de upload ([guia oficial](https://docs.flutter.dev/deployment/android#signing-the-app)) e guarde-a em local seguro.
2. Configure `android/key.properties` e o `signingConfig` de release.
3. Gere o pacote da loja com `flutter build appbundle`.

## iOS (iPhone)

Exige um Mac com Xcode e uma conta Apple Developer. Antes de compilar, adicione em `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>O app usa o Bluetooth para se conectar à impressora Leopardo.</string>
```

Para o "Compartilhar › Leopardo" no iPhone é preciso criar uma *Share Extension* (veja a documentação do pacote `receive_sharing_intent`). No Android isso já funciona.

## Estrutura

```
lib/
  main.dart                    abas (Início, Impressoras, Ajustes) e arquivos compartilhados
  theme.dart                   cores da marca
  screens/
    home_screen.dart           tela Início
    connect_screen.dart        busca e conexão Bluetooth
    file_print_screen.dart     PDF ou imagem
    receipt_screen.dart        texto livre e recibo
    pix_screen.dart            cobrança PIX
    settings_screen.dart       loja, logo, chave PIX, papel
  services/
    printer_service.dart       BLE: busca, conexão, envio em blocos
    escpos.dart                comandos ESC/POS
    raster.dart                conversão para preto e branco (limiar ou pontilhado)
    receipt_renderer.dart      desenho de recibo, PIX e página de teste
    pix.dart                   PIX copia e cola (BR Code + CRC16)
    settings.dart              preferências salvas no aparelho
    history.dart               últimas impressões (desta sessão)
```

## Limitações conhecidas desta versão

- Impressoras com comandos ESC/POS (BLE, Bluetooth clássico ou USB).
- O histórico de "Recentes" é apagado quando o app fecha.
- O nível de bateria só aparece se a impressora informar pelo serviço padrão de bateria do BLE.
- As fontes são as do sistema; as do protótipo (Archivo e IBM Plex) podem ser adicionadas em `assets/` depois.
