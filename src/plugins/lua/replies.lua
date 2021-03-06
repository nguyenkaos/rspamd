--[[
Copyright (c) 2016, Vsevolod Stakhov <vsevolod@highsecure.ru>
Copyright (c) 2016, Andrew Lewis <nerf@judo.za.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
]]--

if confighelp then
  return
end

-- A plugin that implements replies check using redis

-- Default port for redis upstreams
local redis_params
local settings = {
  action = nil,
  expire = 86400, -- 1 day by default
  key_prefix = 'rr',
  message = 'Message is reply to one we originated',
  symbol = 'REPLY',
  score = -4, -- Default score
  use_auth = true,
  use_local = true,
}

local rspamd_logger = require 'rspamd_logger'
local hash = require 'rspamd_cryptobox_hash'
local lua_util = require 'lua_util'
local lua_redis = require 'lua_redis'
local N = "replies"

local function make_key(goop)
  local h = hash.create()
  h:update(goop)
  local key = h:base32():sub(1, 20)
  key = settings['key_prefix'] .. key
  return key
end

local function replies_check(task)
  local function redis_get_cb(err, data)
    if err ~= nil then
      rspamd_logger.errx(task, 'redis_get_cb received error: %1', err)
      return
    end
    if data == '1' then
      -- Hash was found
      task:insert_result(settings['symbol'], 1.0)
      if settings['action'] ~= nil then
        local ip_addr = task:get_ip()
        if (settings.use_auth and
            task:get_user()) or
            (settings.use_local and ip_addr and ip_addr:is_local()) then
          rspamd_logger.infox(task, "not forcing action for local network or authorized user");
        else
          task:set_pre_result(settings['action'], settings['message'])
        end
      end
    end
  end
  -- If in-reply-to header not present return
  local irt = task:get_header_raw('in-reply-to')
  if irt == nil then
    return
  end
  -- Create hash of in-reply-to and query redis
  local key = make_key(irt)

  local ret = lua_redis.redis_make_request(task,
    redis_params, -- connect params
    key, -- hash key
    false, -- is write
    redis_get_cb, --callback
    'GET', -- command
    {key} -- arguments
  )

  if not ret then
    rspamd_logger.errx(task, "redis request wasn't scheduled")
  end
end

local function replies_set(task)
  local function redis_set_cb(err)
    if err ~=nil then
      rspamd_logger.errx(task, 'redis_set_cb received error: %1', err)
    end
  end
  -- If sender is unauthenticated return
  local ip = task:get_ip()
  if settings.use_auth and task:get_user() then
    rspamd_logger.debugm(N, task, 'sender is authenticated')
  elseif settings.use_local and (ip and ip:is_local()) then
    rspamd_logger.debugm(N, task, 'sender is from local network')
  else
    return
  end
  -- If no message-id present return
  local msg_id = task:get_header_raw('message-id')
  if msg_id == nil then
    return
  end
  -- Create hash of message-id and store to redis
  local key = make_key(msg_id)
  rspamd_logger.debugm(N, task, 'storing message-id for replies check')
  local ret = lua_redis.redis_make_request(task,
    redis_params, -- connect params
    key, -- hash key
    true, -- is write
    redis_set_cb, --callback
    'SETEX', -- command
    {key, tostring(settings['expire']), "1"} -- arguments
  )
  if not ret then
    rspamd_logger.errx(task, "redis request wasn't scheduled")
  end
end

local opts = rspamd_config:get_all_opt('replies')
if not (opts and type(opts) == 'table') then
  rspamd_logger.infox(rspamd_config, 'module is unconfigured')
  return
end
if opts then
  redis_params = lua_redis.parse_redis_server('replies')
  if not redis_params then
    rspamd_logger.infox(rspamd_config, 'no servers are specified, disabling module')
    lua_util.disable_module(N, "redis")
  else
    rspamd_config:register_symbol({
      name = 'REPLIES_SET',
      type = 'idempotent',
      callback = replies_set,
      priority = 5,
      group = "replies",
    })
    local id = rspamd_config:register_symbol({
      name = 'REPLIES_CHECK',
      type = 'prefilter,nostat',
      callback = replies_check,
      priority = 10,
      group = "replies"
    })
    rspamd_config:register_symbol({
      name = settings['symbol'],
      parent = id,
      type = 'virtual',
      score = settings.score,
      group = "replies",
    })
  end

  for k,v in pairs(opts) do
    settings[k] = v
  end
end
