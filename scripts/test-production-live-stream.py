#!/usr/bin/env python3
"""生产环境 (https://llm.kxpms.cn) 泳道组件验证"""

import asyncio
import json
import ssl
import urllib.request
from playwright.async_api import async_playwright

ctx_ssl = ssl.create_default_context()
ctx_ssl.check_hostname = False
ctx_ssl.verify_mode = ssl.CERT_NONE


def api_login():
    login_data = json.dumps(
        {"username": "admin", "password": "Veritrans&9527"}
    ).encode()
    req = urllib.request.Request(
        "https://llm.kxpms.cn/api/auth/token",
        data=login_data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10, context=ctx_ssl) as resp:
        return json.loads(resp.read())


async def main():
    print("📡 测试生产环境 https://llm.kxpms.cn ...")

    login = api_login()
    jwt_token = login.get("access_token", "")
    user = login.get("user", {})
    print(f"  ✅ JWT 登录成功 ({len(jwt_token)} 字符)")
    print(
        f"  👤 用户: {user.get('username')} role={user.get('role')} tenant={user.get('tenant_id')}"
    )

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        ctx = await browser.new_context(
            viewport={"width": 1920, "height": 1080},
            ignore_https_errors=True,
        )
        await ctx.add_init_script(
            f"""
            localStorage.setItem('llmgw_jwt_token', '{jwt_token}');
            localStorage.setItem('llmgw_user_info', JSON.stringify({json.dumps(user)}));
            """
        )

        page = await ctx.new_page()

        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))

        await page.goto("https://llm.kxpms.cn/", wait_until="domcontentloaded")
        await asyncio.sleep(10)  # 给 WS 连接和数据加载时间

        info = await page.evaluate(
            """() => {
            return {
                title: document.title,
                url: location.href,
                hasLanes: !!document.querySelector('.live-stream-lanes'),
                groupBtns: document.querySelectorAll('.live-stream-lanes__group-btn').length,
                lanes: document.querySelectorAll('.live-stream-lane').length,
                hasLegend: !!document.querySelector('.live-legend'),
                btnsText: Array.from(document.querySelectorAll('.live-stream-lanes__group-btn')).map(b => b.innerText.trim()),
                status: document.querySelector('.live-stream-lanes__status')?.innerText?.trim() || 'NOT FOUND',
                count: document.querySelector('.live-stream-lanes__count')?.innerText?.trim() || 'NOT FOUND',
                pauseBtn: document.querySelector('.live-stream-lanes__btn')?.innerText?.trim() || 'NOT FOUND',
                legendRows: document.querySelectorAll('.live-legend__row').length,
            };
        }"""
        )

        # 测试切换分组模式
        group_btns = await page.query_selector_all(".live-stream-lanes__group-btn")
        mode_results = []
        if len(group_btns) == 3:
            print("\n  🧪 测试三种分组模式切换...")
            for i, name in enumerate(["按原厂", "按供应商", "按模型"]):
                await group_btns[i].click()
                await asyncio.sleep(2)
                active_text = await page.evaluate(
                    """() => {
                    const a = document.querySelector('.live-stream-lanes__group-btn--active');
                    return a ? a.innerText.trim() : 'NONE';
                }"""
                )
                passed = name == active_text
                mode_results.append(
                    {"name": name, "active": active_text, "passed": passed}
                )
                mark = "✅" if passed else "❌"
                print(f"    {mark} {name} → 激活='{active_text}'")
                await page.screenshot(
                    path=f"/tmp/live-stream-verify/prod-group-{name}.png",
                    full_page=True,
                )

        print("\n" + "=" * 50)
        print("📊 生产环境 (https://llm.kxpms.cn) 验证报告")
        print("=" * 50)
        print(f"页面: {info['url']}")
        print(f"标题: {info['title']}")
        print(f"泳道组件: {'✅' if info['hasLanes'] else '❌'}")
        print(
            f"分组按钮数: {info['groupBtns']} {'✅' if info['groupBtns'] == 3 else '❌'}"
        )
        print(f"分组按钮文本: {info['btnsText']}")
        print(f"泳道数量: {info['lanes']}")
        print(f"连接状态: {info['status']}")
        print(f"暂停按钮: {info['pauseBtn']}")
        print(f"缓存统计: {info['count']}")
        print(f"图例组件: {'✅' if info['hasLegend'] else '❌'}")
        print(f"图例行数: {info['legendRows']}")

        if errors:
            print(f"\n⚠️  JS 错误 ({len(errors)}):")
            for e in errors[:3]:
                print(f"  - {e[:200]}")

        await page.screenshot(
            path="/tmp/live-stream-verify/production-final.png", full_page=True
        )
        print("\n📸 截图: /tmp/live-stream-verify/production-final.png")

        await browser.close()


asyncio.run(main())
