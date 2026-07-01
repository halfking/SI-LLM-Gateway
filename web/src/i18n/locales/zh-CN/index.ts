// zh-CN/index.ts — 聚合简体中文各模块。新增模块在此 import + 合并。
import common from './common'
import nav from './nav'
import login from './login'
import app from './app'
import errors from './errors'
import users from './users'
import keys from './keys'

export default {
  common,
  nav,
  login,
  app,
  errors,
  users,
  keys,
}
