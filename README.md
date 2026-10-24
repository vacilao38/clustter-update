# Clustter Update

Componente compartilhado para todos os apps novos e versões futuras da Clustter cores. Windows e Android consultam apenas o catálogo público HTTPS, avisam dentro do app quando existe versão superior e abrem a página oficial para download. Não baixa nem executa instaladores automaticamente, não usa conta e não envia projetos, arquivos, identificadores de aparelho ou versão instalada ao servidor.

## Integrar

Adicione a dependência Git fixada em um commit aprovado e envolva o `child` de `MaterialApp.builder`:

```dart
builder: (context, child) => ClustterUpdate(
  appId: 'chain', appName: 'Chain', child: child!,
),
```

A versão instalada vem de package_info_plus; não mantenha uma constante duplicada. Novas distribuições devem incrementar a versão semântica em pubspec.yaml. Build numbers Android por ABI não são usados como versão do protocolo. A verificação ocorre ao abrir, a cada 30 minutos enquanto o app está ativo e ao retornar ao app, respeitando esse intervalo. Falta de rede/versão indisponível/cache inválido nunca impede o trabalho local. Dispensar o aviso silencia apenas aquela versão; uma nova versão volta a avisar.

O aviso pode aparecer apenas nas versões que já incluem este componente. Apps antigos precisam de uma primeira atualização manual para adquiri-lo. Não há notificação do sistema com o aplicativo fechado nem instalação silenciosa no aparelho.

## Publicar uma atualização

O feed é `https://vacilao38.github.io/clustter-cores-downloads/updates.json`:

```json
{"protocol":"clustter.update","schema":1,"apps":{"chain":{"windows":{"version":"1.1.1","page":"https://vacilao38.github.io/clustter-cores-downloads/#chain","notes":"Avisos de atualização e instalador Windows."}}}}
```

Cada plataforma só entra no feed depois de seus pacotes estarem públicos e verificados. Publicar código não muda o feed. Os links aceitos apontam exclusivamente à página do próprio produto no domínio/caminho oficial, sem parâmetros, credenciais ou redirecionamentos. Limite de 256 KiB, timeout de 8 segundos e HTTPS com validação normal do sistema. O provedor da hospedagem recebe os metadados normais de uma requisição HTTP, incluindo IP; não há telemetria própria ou dados pessoais no payload.

O catálogo da vitrine é a fonte dos cards e das versões. O processo de release deve atualizar pacotes, catálogo e feed de forma coordenada. Produtos não autorizados não devem ser incluídos. Testes usam versões e dados sintéticos, sem oferecer versões fictícias no feed público.

## Instaladores Windows

`tool/build-installer.py` gera um instalador NSIS por usuário a partir do build Release completo. AppId/registro/caminho são estáveis por produto. Não precisa de administrador, cria atalho no menu Iniciar e entrada de desinstalação, preserva o diretório de suporte dos aplicativos e pede para fechar a instância instalada antes de substituir arquivos. A desinstalação remove apenas arquivos empacotados; não apaga a biblioteca, projetos ou preferências.

O compilador NSIS portátil vem do canal oficial e fica em `.tools/` ignorado. Executáveis gerados ficam em `dist/` do app e não são enviados pelo sincronizador. Um certificado de assinatura digital Windows não acompanha este projeto: o instalador não anuncia um editor verificado. Não confundir assinatura do editor Windows com a assinatura Android.

Com o build Windows Release pronto e NSIS 3.13 em `.tools/nsis-3.13`, execute na raiz deste repositório:

```powershell
py -3 tool/build-installer.py ../chain_app --name Chain
py -3 tool/prepare-android.py ../chain_app --name Chain --sdk "$env:LOCALAPPDATA/Android/Sdk" --java-home "C:/Program Files/Android/Android Studio/jbr"
```

Substitua o projeto e nome pelo produto correspondente. O primeiro comando confere a versão real do executável e inclui o runtime C++ local. O segundo confere os três APKs Release, versão, ABI, certificado esperado, permissão INTERNET e alinhamento ZIP de 16 KiB antes de copiar. Outro certificado exige `--certificate` explícito, obtido da versão anterior distribuída. O manifesto Android principal precisa da permissão INTERNET para consultar o feed em Release. Os relatórios e pacotes ficam no `dist/<versão>/` do app, ignorado pelo Git.

Em outro PC, inclua `update` na seleção de projetos para recuperar estas ferramentas. SDKs, NSIS e chaves não passam pelo sincronizador. O instalador usa um caminho estável a partir da primeira instalação; uma versão antiga extraída de ZIP precisa da primeira instalação manual. Dados de suporte continuam no mesmo diretório de cada aplicativo.

`tool/publish-release.py` publica os pacotes verificados somente após autorização explícita para a distribuição. Não faz parte do sync ou do build. Os arquivos devem estar públicos e verificados antes de mudar o catálogo. `dart tool/check_feed.dart` valida o feed HTTPS real com o mesmo cliente distribuído nos apps.

## Validar

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

Fontes: [package_info_plus](https://pub.dev/packages/package_info_plus), [url_launcher](https://pub.dev/packages/url_launcher), [NSIS](https://nsis.sourceforge.io/Docs/).
