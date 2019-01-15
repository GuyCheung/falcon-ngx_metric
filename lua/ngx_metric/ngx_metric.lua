-- Copyright (C) Guy Cheung
--

local util = require "ngx_metric.util"
local counter = require "ngx_metric.counter"
local chunkhisto = require "ngx_metric.chunk_histogram"

local _M = { _VERSION = '0.0.1' }
local mt = { __index = _M }

local function cut_uri(uri, section_len)
    local uri_a = util.str_split(uri, "/")
    local res = ""
    for i = 1, math.min(section_len, #uri_a) do
        res = res .. "/" .. uri_a[i]
    end
    return res
end

function _M.new(_, dict, item_sep, uri_section_len)
    local self = {
        dict = dict,
        item_sep = item_sep,
        cutted_uri = cut_uri(ngx.var.uri, uri_section_len),
    }
    return setmetatable(self, mt)
end

function _M.req_sign(self, t)
    return t .. self.item_sep .. ngx.var.server_name .. self.item_sep .. self.cutted_uri
end

---- 请求次数统计, counter类型
function _M.query_count(self)
    local status_code = tonumber(ngx.var.status)
    if status_code < 400 then
        local metric = self:req_sign("query_count")
        counter.add(self.dict, metric, 1)
    end
end

-- latency
function _M.latency(self)

    local metric = self:req_sign("latency")
    local latency = tonumber(ngx.var.request_time) or 0
    chunkhisto.add(self.dict, metric, latency)

end

-- http error status stat
function _M.err_count(self)

    local status_code = tonumber(ngx.var.status)
    if status_code >= 400 then
        local metric_err_qc = self:req_sign("err_count")
        local metric_err_detail = metric_err_qc.."|"..status_code
        counter.add(self.dict, metric_err_detail, 1)
    end

end

---- upstream_time统计, timer类型
function _M.upstream_time(self)

    local upstream_response_time_s = ngx.var.upstream_response_time or ""
    upstream_response_time_s = string.gsub(string.gsub(upstream_response_time_s, ":", ","), " ", "")

    if upstream_response_time_s == "" then
        return
    end

    local resp_time_arr = util.str_split(upstream_response_time_s, ",")

    local metric = self:req_sign("upstream_contacts")
    counter.add(self.dict, metric, #(resp_time_arr))

    local duration = 0.0
    for _, t in pairs(resp_time_arr) do
        if tonumber(t) then
            duration = duration + tonumber(t)
        end
    end

    local metric_upstream_latency = self:req_sign("upstream_latency")
    chunkhisto.add(self.dict, metric_upstream_latency, duration)

end

function _M.record(self)
    self:query_count()
    self:err_count()
    self:latency()
    self:upstream_time()
end

return _M
