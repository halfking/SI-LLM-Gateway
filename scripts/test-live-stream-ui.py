#!/usr/bin/env python3
"""
实时请求流泳道 UI 实测验证脚本
使用 Playwright 进行浏览器自动化验证
按 rule 11 §6 要求进行视频级交互验证
"""

import asyncio
import sys
import os
import json
import urllib.request
from playwright.async_api import async_playwright

SCREENSHOT_DIR = "/tmp/live-stream-verify"
os.makedirs(SCREENSHOT_DIR, exist_ok=True)


class LiveStreamVerifier:
    def __init__(self):
        self.results = []
        self.page = None
        self.browser = None
        self.context = None
        self.pw = None

    def log(self, status, message):
        icon = "✅" if status == "PASS" else "❌" if status == "FAIL" else "ℹ️"
        print(f"  {icon} {message}")
        self.results.append({"status": status, "message": message})

    async def setup(self):
        print("📱 启动浏览器...")
        self.pw = await async_playwright().start()
        self.browser = await self.pw.chromium.launch(headless=False, slow_mo=800)
        self.context = await self.browser.new_context(
            viewport={"width": 1920, "height": 1080},
            locale="zh-CN",
        )
        self.page = await self.context.new_page()
        print("✅ 浏览器已启动")

    async def teardown(self):
        if self.browser:
            await self.browser.close()
        if self.pw:
            await self.pw.stop()
        print("✅ 浏览器已关闭")

    def api_login(self):
        """通过后端 API 登录获取 api_key 和用户信息"""
        try:
            login_data = json.dumps({"username": "admin", "password": "admin"}).encode()
            req = urllib.request.Request(
                "http://localhost:8781/api/auth/token",
                data=login_data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                login_resp = json.loads(resp.read())

            # 获取用户信息
            api_key = login_resp.get("api_key", "")
            me_req = urllib.request.Request(
                "http://localhost:8781/api/auth/me",
                headers={"Authorization": f"Bearer {api_key}"},
                method="GET",
            )
            with urllib.request.urlopen(me_req, timeout=5) as me_resp:
                user_info = json.loads(me_resp.read())

            return {"api_key": api_key, "user": user_info}
        except Exception as e:
            print(f"  ❌ API 登录异常: {e}")
            return None

    async def navigate_to_dashboard(self):
        print("\n📍 步骤1: 通过 API 登录并导航...")

        # 1. 调用后端 API 登录
        login_resp = self.api_login()
        if not login_resp or "api_key" not in login_resp:
            self.log("FAIL", "API 登录失败")
            return False

        api_key = login_resp["api_key"]
        user_info = login_resp.get("user", {})
        self.log("PASS", f"API 登录成功，用户角色: {user_info.get('role')}")

        # 2. 使用 addInitScript 在页面加载前注入 localStorage
        await self.context.add_init_script(f"""
            localStorage.setItem('llmgw_api_key', '{api_key}');
            localStorage.setItem('llmgw_user_info', JSON.stringify({json.dumps(user_info)}));
        """)

        # 3. 访问首页
        await self.page.goto("http://localhost:5780/")
        await self.page.wait_for_load_state("networkidle")
        await asyncio.sleep(8)  # 等待所有数据加载和 WebSocket 连接

        current_url = self.page.url
        print(f"  当前 URL: {current_url}")
        await self.screenshot("01-after-login")
        return True

    async def find_lanes_component(self):
        print("\n📍 步骤2: 查找实时请求流泳道组件...")
        await self.screenshot("02-after-navigation")

        # 先检查页面内容
        title = await self.page.title()
        print(f"  页面标题: {title}")

        # 列出页面上所有 main 元素内容
        main_content = await self.page.evaluate("""() => {
            const main = document.querySelector('main');
            if (!main) return 'no main element';
            return main.innerText.substring(0, 500);
        }""")
        print(f"  main 内容预览: {main_content[:200]}")

        # 列出页面上所有组件类名前缀
        all_classes = await self.page.evaluate("""() => {
            const elements = document.querySelectorAll('[class]');
            const prefixes = new Set();
            elements.forEach(el => {
                el.className.split(' ').forEach(c => {
                    if (c && c.includes('-')) {
                        const prefix = c.split('-')[0];
                        if (prefix.length > 2) prefixes.add(prefix);
                    }
                });
            });
            return Array.from(prefixes).sort();
        }""")
        print(f"  组件前缀: {all_classes[:20]}")

        lanes = await self.page.query_selector(".live-stream-lanes")
        if not lanes:
            old_stream = await self.page.query_selector(".live-stream")
            if old_stream:
                self.log(
                    "FAIL", "页面使用的是旧版布局 (.live-stream)，不是新版泳道布局"
                )
                return False

            live_classes = await self.page.evaluate("""() => {
                const elements = document.querySelectorAll('[class]');
                const classes = new Set();
                elements.forEach(el => {
                    el.className.split(' ').forEach(c => {
                        if (c && c.startsWith('live-')) classes.add(c);
                    });
                });
                return Array.from(classes);
            }""")
            self.log("INFO", f"页面上的 live-* 类: {live_classes}")

            if not live_classes:
                self.log("FAIL", "页面上没有找到任何 live-* 组件")
                return False

            self.log("FAIL", "未找到泳道组件 .live-stream-lanes")
            return False

        self.log("PASS", "找到泳道组件 .live-stream-lanes")
        return True

    async def verify_group_modes(self):
        print("\n📍 步骤3: 验证三种分组模式切换...")

        group_btns = await self.page.query_selector_all(".live-stream-lanes__group-btn")
        print(f"  找到 {len(group_btns)} 个分组按钮")

        if len(group_btns) != 3:
            self.log("FAIL", f"期望3个分组按钮，实际找到 {len(group_btns)} 个")
            return False

        self.log("PASS", "找到3个分组按钮")

        btn_texts = []
        for i, btn in enumerate(group_btns):
            text = await btn.inner_text()
            btn_texts.append(text)
            print(f"  按钮 {i + 1}: {text}")

        expected_keywords = ["原厂", "供应商", "模型"]
        for keyword in expected_keywords:
            if any(keyword in t for t in btn_texts):
                self.log("PASS", f"找到包含'{keyword}'的按钮")
            else:
                self.log("FAIL", f"未找到包含'{keyword}'的按钮")

        modes = ["vendor", "provider", "model"]
        mode_names = ["按原厂", "按供应商", "按模型"]
        for i, (mode, name) in enumerate(zip(modes, mode_names)):
            print(f"\n  🧪 测试分组模式: {name}")
            await group_btns[i].click()
            await asyncio.sleep(2)

            await self.screenshot(f"03-group-{mode}")

            active_btn = await self.page.query_selector(
                ".live-stream-lanes__group-btn--active"
            )
            if active_btn:
                active_text = await active_btn.inner_text()
                if name in active_text or active_text.strip() == name:
                    self.log("PASS", f"模式 {name} 已激活，按钮高亮正确")
                else:
                    self.log(
                        "FAIL", f"激活按钮文本不匹配: 期望'{name}', 实际'{active_text}'"
                    )
            else:
                self.log("FAIL", f"模式 {name} 切换后未找到激活按钮")

            lanes = await self.page.query_selector_all(".live-stream-lane")
            lane_count = len(lanes)
            print(f"    泳道数量: {lane_count}")
            if lane_count <= 7:
                self.log("PASS", f"泳道数量 {lane_count} 在合理范围内 (≤7)")
            else:
                self.log("FAIL", f"泳道数量过多: {lane_count}")

        return True

    async def verify_header_controls(self):
        print("\n📍 步骤4: 验证标题栏控件...")

        status = await self.page.query_selector(".live-stream-lanes__status")
        if status:
            status_text = await status.inner_text()
            self.log("PASS", f"连接状态按钮存在: '{status_text.strip()}'")

            print("  🧪 测试点击连接状态按钮...")
            await status.click()
            await asyncio.sleep(1)

            ws_url_div = await self.page.query_selector(".live-stream-lanes__ws-url")
            if ws_url_div:
                ws_url = await ws_url_div.inner_text()
                self.log("PASS", f"WebSocket 地址显示: {ws_url.strip()}")
            else:
                self.log("INFO", "未显示 WS 地址（可能是管理员权限限制）")

            await self.screenshot("04-ws-url-shown")

            await status.click()
            await asyncio.sleep(1)
        else:
            self.log("FAIL", "未找到连接状态按钮")

        pause_btn = await self.page.query_selector(".live-stream-lanes__btn")
        if pause_btn:
            btn_text = await pause_btn.inner_text()
            self.log("PASS", f"暂停按钮存在: '{btn_text.strip()}'")

            await pause_btn.click()
            await asyncio.sleep(1)
            new_text = await pause_btn.inner_text()
            self.log("PASS", f"点击后按钮文本: '{new_text.strip()}'")

            await self.screenshot("05-paused")

            await pause_btn.click()
            await asyncio.sleep(1)
            resumed_text = await pause_btn.inner_text()
            self.log("PASS", f"再次点击后按钮文本: '{resumed_text.strip()}'")
        else:
            self.log("FAIL", "未找到暂停按钮")

        count_badge = await self.page.query_selector(".live-stream-lanes__count")
        if count_badge:
            count_text = await count_badge.inner_text()
            self.log("PASS", f"缓存/窗口统计存在: '{count_text.strip()}'")

            if "/" in count_text:
                self.log("PASS", "统计格式包含 / 分隔符")
            else:
                self.log("FAIL", f"统计格式不正确: '{count_text.strip()}'")
        else:
            self.log("FAIL", "未找到缓存/窗口统计")

    async def verify_lanes_display(self):
        print("\n📍 步骤5: 验证泳道显示...")

        lanes = await self.page.query_selector_all(".live-stream-lane")
        if not lanes:
            self.log("FAIL", "未找到任何泳道")
            return

        self.log("PASS", f"找到 {len(lanes)} 个泳道")

        for i, lane in enumerate(lanes[:3]):
            name = await lane.query_selector(".live-stream-lane__name")
            count = await lane.query_selector(".live-stream-lane__count")

            if name and count:
                name_text = (await name.inner_text()).strip()
                count_text = (await count.inner_text()).strip()

                if count_text.startswith("(") and count_text.endswith(")"):
                    self.log("PASS", f"泳道 {i + 1}: {name_text} {count_text}")
                else:
                    self.log("FAIL", f"泳道 {i + 1} 计数格式不正确: '{count_text}'")
            else:
                self.log("FAIL", f"泳道 {i + 1} 缺少名称或计数")

            blocks = await lane.query_selector_all(".live-block")
            print(f"    包含 {len(blocks)} 个请求块")

    async def verify_legend(self):
        print("\n📍 步骤6: 验证图例...")

        legend = await self.page.query_selector(".live-legend")
        if legend:
            self.log("PASS", "图例组件存在")

            rows = await legend.query_selector_all(".live-legend__row")
            self.log("PASS", f"图例有 {len(rows)} 行")

            for i, row in enumerate(rows):
                heading = await row.query_selector(".live-legend__heading")
                if heading:
                    heading_text = (await heading.inner_text()).strip()
                    items = await row.query_selector_all(".live-legend__item")
                    self.log(
                        "PASS", f"图例行 {i + 1}: {heading_text} ({len(items)} 项)"
                    )
        else:
            self.log("FAIL", "未找到图例组件")

    async def screenshot(self, name):
        path = f"{SCREENSHOT_DIR}/{name}.png"
        await self.page.screenshot(path=path, full_page=True)
        print(f"    📸 {path}")

    async def run(self):
        await self.setup()

        try:
            ok = await self.navigate_to_dashboard()
            if not ok:
                return False

            found = await self.find_lanes_component()
            if not found:
                self.log("FAIL", "无法继续：未找到泳道组件")
                await self.screenshot("FAIL-no-component")
                return False

            await self.verify_group_modes()
            await self.verify_header_controls()
            await self.verify_lanes_display()
            await self.verify_legend()

            await self.screenshot("07-final")
            return True

        except Exception as e:
            self.log("FAIL", f"测试过程出错: {e}")
            await self.screenshot("ERROR-exception")
            import traceback

            traceback.print_exc()
            return False

        finally:
            await self.teardown()

    def print_report(self):
        print("\n" + "=" * 60)
        print("📊 验证报告")
        print("=" * 60)

        pass_count = sum(1 for r in self.results if r["status"] == "PASS")
        fail_count = sum(1 for r in self.results if r["status"] == "FAIL")
        info_count = sum(1 for r in self.results if r["status"] == "INFO")
        total = len(self.results)

        print(f"\n总计: {total} 项检查")
        print(f"  ✅ 通过: {pass_count}")
        print(f"  ❌ 失败: {fail_count}")
        print(f"  ℹ️  信息: {info_count}")
        if total > 0:
            print(f"  通过率: {pass_count / total * 100:.1f}%")

        if fail_count > 0:
            print(f"\n❌ 失败项:")
            for r in self.results:
                if r["status"] == "FAIL":
                    print(f"  - {r['message']}")

        print(f"\n📸 截图保存在: {SCREENSHOT_DIR}/")
        return fail_count == 0


async def main():
    verifier = LiveStreamVerifier()
    await verifier.run()
    all_passed = verifier.print_report()
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    asyncio.run(main())
