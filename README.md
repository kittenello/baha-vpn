# baha vpn

нативный ios-клиент для собственных серверов на базе xray-core. приватный прототип,
swiftui, ios 17+. приложение не выдаёт серверы и не продаёт доступ.

![концепт интерфейса](design-concept.png)

## реализовано

- vless-ссылки: tcp, websocket, xhttp; tls, reality и vision.
- vmess aead-ссылки: tcp/websocket и tls.
- импорт из буфера, текстового файла, камеры qr, изображения qr и открытия vless/vmess-ссылок.
- https-подписки в plain-text/base64, квоты из `subscription-userinfo`, ручное обновление и обновление при открытии приложения по интервалу.
- привязка устройства для совместимых панелей: `x-hwid`, `x-device-os`, `x-ver-os`, `x-device-model`; понятные ошибки лимита устройств remnawave.
- список серверов, поиск, избранное, выбор, удаление и tcp-задержка.
- сохранение состояния в aes-gcm; ключ в keychain, запись атомарная.
- системный packet tunnel с xray, ipv4/ipv6, dns, подключением/отключением и реальными счётчиками пакетов.
- системное впн on demand после первого подключения.

неподдерживаемый протокол или некорректная строка отменяет весь импорт/обновление.
старые серверы подписки сохраняются; избранное и выбранный сервер переживают успешное обновление.
tcp-задержка не означает, что авторизация на сервере или само впн-соединение успешно.

## сборка через actions

workflow `ios prototype` запускается при push в main и вручную.
сначала выполняет тесты core, затем собирает release-приложение и packet tunnel для iphone,
упаковывает unsigned ipa, собирает симулятор, проверяет через xcuittest импорт и сохранение
профиля/избранного после перезапуска приложения, запускает приложение и сохраняет реальный скриншот.
артефакт `baha-vpn-prototype`: `baha-vpn-unsigned.ipa`, simulator app и `preview.png`.
`build-logs`: логи xcodebuild. демо-серверы добавляются только с аргументом `--preview-data`,
помечены `демо`, не сохраняются и не являются рабочими серверами.

unsigned ipa нельзя установить как обычное подписанное приложение.
для настоящего запуска на iphone нужна подпись apple developer с network extension capability
для приложения и расширения. vpn невозможно проверить полноценно в симуляторе.
успешная сборка подтверждает компиляцию; подключение к настоящему серверу проверяется отдельно на iphone.

## локальная сборка на macos

нужны xcode 16+ со swift 6, ios sdk и ios simulator runtime, homebrew и xcodegen.

```sh
brew install xcodegen
xcodegen generate
open BahaVPN.xcodeproj
```

в xcode выбери свою developer team для обоих targets (`BahaVPN`, `PacketTunnel`)
и уникальные bundle identifiers. идентификатор расширения должен быть идентификатором
приложения с суффиксом `.tunnel`. включи `network extensions → packet tunnel`
в app id и signing для обоих targets. app groups не требуются: конфигурация передаётся
через `NETunnelProviderProtocol.providerConfiguration`.

```sh
cd Core
swift test
```

## устройство проекта

- `App/`: swiftui, keychain/aes-gcm, vpn manager, камера, фото и tcp probes.
- `Core/`: модели, разбор ссылок и подписок, проверка и генерация xray json, тесты.
- `Tunnel/`: network extension и packet-flow bridge.
- `ThirdParty/SwiftyXrayKit/`: vendored wrapper 2.0.0 с лицензией и зафиксированным origin.
- `project.yml`: воспроизводимая генерация xcode-проекта.
- `.github/workflows/ios.yml`: тесты и unsigned-сборка.

## ядро и ограничения прототипа

используется [swiftyxraykit](https://github.com/dima-u/SwiftyXrayKit), закреплённый
на commit `3c5405521ae547de110f6ea65df00b1c05f6a0bc`, и checksum-pinned
[libxray-apple](https://github.com/dima-u/libXray-apple/releases/tag/v26.3.27-ios),
на основе официальных [libxray](https://github.com/XTLS/libXray) и
[xray-core](https://github.com/XTLS/Xray-core). сборка ядра содержит патчи для
socketpair tun в ios и ограничения памяти. это не неизменённый официальный бинарник xtls.

trojan, shadowsocks, hysteria2, wireguard, grpc, raw json и сложные правила маршрутизации
в этой версии не поддерживаются. маршрутизация: весь трафик через выбранный профиль.
обновление подписок в фоне по точному расписанию, виджеты, смена значка и журналы не добавлены.
квота отображается только когда её передаёт сервер подписки; статистика туннеля считает ip-пакеты,
а не байты, учтённые биллингом провайдера.

профили не отправляются разработчику клиента. приложение обращается к введённым подпискам,
серверам и выбранному dns. при каждом запросе подписки провайдер получает `x-hwid`,
тип устройства и версию ios. постоянный случайный seed хранится в keychain;
из него вычисляется sha-256 идентификатор отдельно для каждого домена провайдера.
это не udid/imei или серийный номер apple. seed не синхронизируется через icloud,
и при переносе на другой iphone создаётся другой идентификатор. сохранение keychain после
удаления приложения определяется ios; пожизненную привязку после удаления клиент не обещает.
идентификатор передаётся серверу подписки, а не добавляется в протокол vless/vmess.
при редиректе на другой домен идентифицирующие заголовки удаляются; подписка с обязательным
hwid на конечном домене должна использовать прямую ссылку этого провайдера.
панель определяет лимиты; один `x-hwid` не является защитой от обхода на уровне сервера.
контракт: https://github.com/remnawave/panel/blob/main/docs/features/hwid-device-limit.md.
конфигурация сохраняется системой в настройках впн; временный plaintext-файл расширения
удаляется после старта ядра.

## лицензии

исходный код клиента — mit (`LICENSE`). swiftyxraykit — apache 2.0,
license и copyright сохранены в `ThirdParty`. xray-core — mpl 2.0;
ссылки на исходники бинарной сборки указаны в `ThirdParty/SwiftyXrayKit/ORIGIN.md`.
