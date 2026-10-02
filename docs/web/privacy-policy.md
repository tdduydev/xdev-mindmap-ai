# Privacy policy page

Source text for <https://xdev.asia/mindmap/privacy>, which the app opens from Settings ▸ Privacy and Help ▸ Privacy Policy (`AppLinks.privacyPolicy`). The same URL goes in App Store Connect. The page is published from the xdev.asia repo (`src/apps/mindmap.en.json`, `.vi.json`), live since 2026-10-03; this file is the source of truth for its wording.

## Keep it true

Every sentence must describe the app as shipped. Change this page, [privacy](../privacy.md), `PrivacyInfo.xcprivacy` and the App Privacy label together when any of these change:

- iCloud sync ships (MM-6 built it; it is live once a build sets `MINDMAP_ICLOUD`): the iCloud section says sync is on while you are signed in to iCloud and how to turn it off; check it again after the account-change test in [cloudkit-sync](../cloudkit-sync.md), *Testing on real devices*.
- Voice input ships (MM-20): same for the voice section; it must stay on the device.
- AI Apps (MCP, MM-46): the "AI apps you connect" section must match Settings ▸ AI Apps; change it when AI apps can write (M5) or when anything but loopback is served.
- Analytics, crash reporting, cloud AI or any network call to xDev is added: rewrite the page before the build ships.

Do not add claims the app does not make good on. Dates are the publish date of the wording.

---

## English

**MindMap AI by xDev: Privacy Policy**

Effective date: 3 October 2026

MindMap AI is built so that your maps stay yours. This policy explains what the app does with your data.

**What we collect.** Nothing. xDev does not run servers for MindMap AI, does not require an account, and does not include analytics, advertising or tracking. Your maps are never sent to xDev.

**Where your maps are stored.** On your device. When iCloud sync is available in the app and you are signed in to iCloud, your maps are also stored in your own private iCloud account, under [Apple's privacy policy](https://www.apple.com/legal/privacy/), so they appear on your other devices. xDev cannot read your iCloud data. To stop syncing, turn off iCloud Sync in MindMap AI ▸ Settings ▸ Data on a Mac, or turn off iCloud for MindMap AI in the Settings app on iPhone and iPad; your maps stay on the device.

**AI features.** AI features use Apple's on-device model (Apple Intelligence). Your text is processed on your device and is not sent to xDev. On devices without Apple Intelligence, the AI features are not shown.

**Voice input.** When voice input is available, speech is turned into text on your device and is not sent to xDev. The app asks for microphone and speech recognition access the first time you use it.

**AI apps you connect (Mac).** You can let AI apps on your Mac, such as Claude Code or ChatGPT, read your maps in MindMap AI ▸ Settings ▸ AI Apps. It is off until you turn it on, and each app needs a token you add there. A connected app can read the titles, notes and structure of your maps while MindMap AI is open, and may send what it reads to its own AI provider under that app's terms and privacy policy; check those before you connect it. MindMap AI does not send this data to xDev. Turn the switch off to stop every app, or revoke one app in the same place.

**Purchases.** Payments are handled by Apple through the App Store. xDev does not receive your payment details.

**Crash reports from Apple.** If you choose to share analytics with app developers in your device settings, Apple may share crash reports and usage statistics with xDev. You control this in your device's privacy settings.

**Deleting your data.** Delete a map in the app to move it to Recently Deleted. It stays there for 30 days so you can restore it, then it is deleted permanently; Delete Permanently removes it straight away. Deleting the app removes the maps stored on that device. Maps in iCloud can be removed in your device's iCloud storage settings.

**Children.** The app does not collect data from anyone, including children.

**Changes.** If this policy changes, we update this page and the date above.

**Contact.** [duy@xdev.asia](mailto:duy@xdev.asia), or see [MindMap AI Support](https://xdev.asia/mindmap/support).

---

## Tiếng Việt

**MindMap AI by xDev: Chính sách quyền riêng tư**

Ngày hiệu lực: 3 tháng 10 năm 2026

MindMap AI được làm để sơ đồ của bạn luôn là của bạn. Chính sách này cho biết ứng dụng làm gì với dữ liệu của bạn.

**Chúng tôi thu thập gì.** Không gì cả. xDev không vận hành máy chủ nào cho MindMap AI, không yêu cầu tài khoản, không có thống kê, quảng cáo hay theo dõi. Sơ đồ của bạn không bao giờ được gửi tới xDev.

**Sơ đồ được lưu ở đâu.** Trên thiết bị của bạn. Khi ứng dụng có đồng bộ iCloud và bạn đã đăng nhập iCloud, sơ đồ còn được lưu trong tài khoản iCloud riêng của bạn, theo [chính sách quyền riêng tư của Apple](https://www.apple.com/legal/privacy/), để có mặt trên các thiết bị khác của bạn. xDev không đọc được dữ liệu iCloud của bạn. Muốn ngừng đồng bộ, trên Mac hãy tắt Đồng bộ iCloud trong MindMap AI ▸ Cài đặt ▸ Dữ liệu, trên iPhone và iPad hãy tắt iCloud cho MindMap AI trong ứng dụng Cài đặt; sơ đồ vẫn nằm trên thiết bị.

**Tính năng AI.** Tính năng AI dùng model chạy trên thiết bị của Apple (Apple Intelligence). Nội dung của bạn được xử lý trên thiết bị và không gửi tới xDev. Trên thiết bị không có Apple Intelligence, tính năng AI không hiện.

**Nhập bằng giọng nói.** Khi ứng dụng có nhập bằng giọng nói, lời nói được chuyển thành chữ trên thiết bị và không gửi tới xDev. Ứng dụng xin quyền micro và nhận dạng giọng nói ở lần đầu bạn dùng.

**Ứng dụng AI bạn kết nối (Mac).** Bạn có thể cho các ứng dụng AI trên Mac, như Claude Code hay ChatGPT, đọc sơ đồ trong MindMap AI ▸ Cài đặt ▸ Ứng dụng AI. Tính năng tắt cho tới khi bạn bật, và mỗi ứng dụng cần một mã truy cập bạn thêm ở đó. Ứng dụng đã kết nối đọc được tiêu đề, ghi chú và cấu trúc sơ đồ khi MindMap AI đang mở, và có thể gửi nội dung đó tới nhà cung cấp AI của họ theo điều khoản và chính sách quyền riêng tư của ứng dụng đó; hãy xem các điều đó trước khi kết nối. MindMap AI không gửi dữ liệu này tới xDev. Tắt công tắc để dừng mọi ứng dụng, hoặc thu hồi từng ứng dụng ở cùng chỗ.

**Mua hàng.** Việc thanh toán do Apple xử lý qua App Store. xDev không nhận thông tin thanh toán của bạn.

**Báo cáo lỗi từ Apple.** Nếu bạn chọn chia sẻ phân tích với nhà phát triển trong cài đặt thiết bị, Apple có thể chia sẻ báo cáo lỗi và thống kê sử dụng với xDev. Bạn quản lý việc này trong cài đặt quyền riêng tư của thiết bị.

**Xoá dữ liệu.** Xoá một sơ đồ trong ứng dụng thì sơ đồ chuyển vào mục Đã xoá gần đây. Sơ đồ được giữ ở đó 30 ngày để bạn khôi phục, sau đó bị xoá vĩnh viễn; Xoá vĩnh viễn sẽ gỡ nó ngay. Xoá ứng dụng sẽ xoá các sơ đồ lưu trên thiết bị đó. Sơ đồ trong iCloud có thể xoá trong phần quản lý dung lượng iCloud của thiết bị.

**Trẻ em.** Ứng dụng không thu thập dữ liệu của bất kỳ ai, kể cả trẻ em.

**Thay đổi.** Khi chính sách này thay đổi, chúng tôi cập nhật trang này và ngày ở trên.

**Liên hệ.** [duy@xdev.asia](mailto:duy@xdev.asia), hoặc xem [Hỗ trợ MindMap AI](https://xdev.asia/vi/mindmap/support).
