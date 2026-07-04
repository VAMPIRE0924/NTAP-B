# NTAP-B

NTAP-B 鏄?NTAP 鐨勮妭鐐圭銆傚畠閮ㄧ讲鍦ㄥ鎴蜂晶缃戝叧鎴栧唴缃戜富鏈猴紝杩炴帴 NTAP-A锛屽畬鎴愯妭鐐归壌鏉冿紝鍒涘缓鏈湴 TAP 璁惧锛屽苟鎸?NTAP-A 涓嬪彂鐨?`bridge_name` 鎺ュ叆鏈湴缃戠粶銆?
NTAP-B 鐨勮璁＄洰鏍囨槸杞婚噺銆佸彲浜や簰瀹夎銆侀€傚悎瀹㈡埛渚ц妭鐐硅澶囥€俉eb 绠＄悊鍜屽鏉傜瓥鐣ヤ笉鏀惧湪 B 绔紝缁熶竴鐢?NTAP-A 绠＄悊銆?
## 涓変釜浠撳簱

NTAP 鎷嗘垚涓変釜骞插噣鐨勬簮鐮佷粨搴擄紝鏈€缁堝彲閮ㄧ讲鏂囦欢缁熶竴鏀惧湪鍚勮嚜 GitHub Release锛?
- [NTAP-A](https://github.com/VAMPIRE0924/NTAP-A): 鍏綉鏈嶅姟绔紝璐熻矗绠＄悊 API銆丼QLite 鐘舵€佸簱銆佽妭鐐?TAP 閴存潈銆乀apHub 涓户銆?- [NTAP-B](https://github.com/VAMPIRE0924/NTAP-B): 鑺傜偣绔紝閮ㄧ讲鍦ㄥ鎴蜂晶缃戝叧鎴栧唴缃戜富鏈猴紝杩炴帴 A 骞舵帴鍏ユ湰鍦扮綉缁溿€?- [NTAP-C](https://github.com/VAMPIRE0924/NTAP-C): 瀹㈡埛绔紝Windows 绔彁渚涘浘褰㈢晫闈紝Linux 绔彁渚涘懡浠よ鍏ュ彛銆?
## 涓嬭浇鍜岄儴缃?
姝ｅ紡閮ㄧ讲璇蜂笅杞?GitHub Release 閲岀殑鏈€缁堝彂甯冨寘锛屼笉瑕佺洿鎺ユ嬁婧愮爜鐩綍閲岀殑涓存椂鏂囦欢閮ㄧ讲銆?
鏈€鏂扮増鏈細

https://github.com/VAMPIRE0924/NTAP-B/releases/latest

瀹㈡埛渚ц妭鐐归€氬父闇€瑕佷粠 Release 涓嬭浇锛?
- 鑺傜偣瀹夎鍖?- 浜や簰瀹夎鑴氭湰
- 璁惧楠岃瘉鑴氭湰
- 杩愯璇存槑

瀹㈡埛鍙嬪ソ鐨勫畨瑁呮柟寮忥細

```sh
sh /tmp/<NTAP-B-install-script> --interactive
```

瀹夎鑴氭湰浼氫緷娆¤闂細

- 鑺傜偣瀹夎鍖呰矾寰?- NTAP-A 鍦板潃
- Node ID
- Node Key
- TAP 鍚嶇О
- 缃戞ˉ棰勬鍚嶇О锛岄€氬父鏄?`br-lan`
- 鏄惁鍚敤鍜屽惎鍔ㄦ湇鍔?- 鏄惁杩愯璁惧楠岃瘉鑴氭湰

鑷姩鍖栭儴缃蹭篃鍙互浣跨敤 Release 璇存槑閲岀殑闈炰氦浜掑弬鏁般€侼ode Key 涓嶅簲鍐欒繘鍏紑鏃ュ織鎴栨埅鍥撅紱瀹夎鑴氭湰杈撳嚭浼氬仛鎺╃爜銆?
## 杩愯鏂瑰紡

鑺傜偣鍖呭畨瑁呭悗浼氭彁渚涙湰鍦版湇鍔″叆鍙ｅ拰閰嶇疆鏂囦欢銆傚父鐢ㄦ搷浣滐細

```sh
/etc/init.d/ntap-b check
/etc/init.d/ntap-b enable
/etc/init.d/ntap-b start
```

`bridge_check_name` 鍙敤浜庢湰鍦板畨瑁呭墠棰勬锛涚湡姝ｈ繍琛屾椂鏄惁鎸傛帴缃戞ˉ锛屼互 NTAP-A 涓嬪彂鐨?`CONFIG_PUSH bridge_name` 涓哄噯銆?
## 婧愮爜鑼冨洿

```text
src/b/       NTAP-B 鑺傜偣绔簮鐮?src/common/  涓夌鍏变韩鍗忚銆佹棩蹇椼€佺綉缁溿€佹椂闂淬€乥uffer 绛夊叕鍏变唬鐮?conf/        鏈€灏忛厤缃ず渚?```

婧愮爜浠撳簱鍙繚瀛樻簮鐮併€侀厤缃牱渚嬨€丷EADME 鍜?LICENSE锛涙渶缁堝彂甯冨寘鍙斁鍦?GitHub Release銆?
## License

GPL-3.0-only. See `LICENSE`.

