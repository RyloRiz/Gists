-- Gists.lua
-- @R0bl0x10501050

-- Rewrite of https://gist.github.com/RuizuKun-Dev/0a5e98d2b200826bc65267d8417efadc by @RuizuKun_Dev

local HTTP = game:GetService("HttpService")
local GISTS_API = "https://api.github.com"

--- Proxy table type
type tbl = { [any]: any }

--- Function to encode data into JSON format
--- @param data The data to be encoded
--- @return The encoded data
local function encode(data: string | tbl?): string?
	return typeof(data) == "string" and data or HTTP:JSONEncode(data)
end

--- Function to decode data from JSON format
-- @param data The data to be decoded
-- @return The decoded data
local function decode(data: string?): tbl
	data = data and data ~= "" and data or "[]"
	return typeof(data) == "table" and data or HTTP:JSONDecode(data)
end

export type Fields = {
	Url: string,
	Method: string,
	Headers: { [string]: string },
	Body: tbl?,
}

export type Response = {
	Body: tbl,
	Success: boolean,
}

--- Function to handle HTTP requests
--- @param fields The request fields
--- @return The response from the request
local function handleRequest(fields: Fields): Response
	local response = HTTP:RequestAsync(fields)

	local responseBody = decode(response.Body)

	if response.Success then
		response.Body = responseBody
	else
		warn(`{response.StatusCode}: {responseBody.message}`)
	end

	return response
end

--- Function to split a string into chunks
--- @param text The text to chunk
--- @param size The desired size of the chunks
--- @return The chunked strings
local function chunk(text: string, size: number): { string }
	local s = {}
	for i = 1, #text, size do
		s[#s + 1] = text:sub(i, i + size - 1)
	end
	return s
end

type IGist = {
	_Purge: (self: IGist) -> nil,
	_URLS: { string },
	id: string,
	name: string,
	new: (secret: string, name: string) -> IGist,
	Read: (self: IGist) -> tbl,
	Write: (self: IGist, newContents: string) -> nil,
}

local Gist: IGist = {} :: IGist

--- Instantiate a new Gist
--- @param secret The GitHub PAT
--- @param name The name of the Gist
--- @param id The internal parameter for loading already-instantiated Gists
function Gist.new(secret: string, name: string, id: string?): IGist
	local self = setmetatable({}, Gist)

	self.secret = secret
	self.name = name

	if id then
		self.id = id
	else
		local req: Fields = {
			Url = GISTS_API + "/gists",
			Method = "POST",
			Headers = {
				["Accept"] = "application/vnd.github+json",
				["Authorization"] = `Bearer {self.secret}`,
			},
			Body = encode({
				description = "Created by Gists.lua",
				files = {
					[`ROBLOXGISTDB_0_{self.name}.txt`] = {
						content = "PLACEHOLDER",
					},
				},
				public = false,
			}),
		}

		local res = handleRequest(req)
		if res.Success and res.Body then
			self.id = res.Body.id
		else
			error(`Request failed at Gist.new()`)
		end
	end

	return self
end

function Gist:_Purge() : nil
	local req: Fields = {
		Url = GISTS_API + `/gists/{self.id}`,
		Method = "DELETE",
		Headers = {
			["Authorization"] = `Bearer {self.secret}`,
		},
	}

	local res = handleRequest(req)
	if res.Success then
		return nil
	else
		error(`Request failed at Gist:_Purge()`)
	end
end

function Gist:Read() : tbl
	local files = {}
	local str = ""
	local req: Fields = {
		Url = GISTS_API + `/gists/{self.id}`,
		Method = "GET",
		Headers = {
			["Authorization"] = `Bearer {self.secret}`,
		},
	}
	local res = handleRequest(req)
	for k, v in pairs(res.Body.files) do
		files[k] = HTTP:GetAsync(v["raw_url"])
	end
	local i = 1
	while true do
		local f = files[`ROBLOXGISTDB_{i}_{self.name}.txt`]
		if f then
			str ..= f
		else
			break
		end
		i += 1
	end
	return HTTP:JSONDecode(str)
end

function Gist:Write(newContents: string) : nil
	local split = chunk(newContents, 1e6)
	local files = {}
	local updatedFilenames: { string } = {}
	for i, contentChunk in ipairs(split) do
		local gistName = `ROBLOXGISTDB_{i}_{self.name}.txt` -- Gist documentation advises against numerical suffixes
		table.insert(updatedFilenames, gistName)
		files[gistName] = {
			content = encode(contentChunk),
		}
	end
	for k, _ in pairs(self._URLS) do
		if table.find(updatedFilenames, k) then
			continue
		else
			files[k] = nil
		end
	end
	local req: Fields = {
		Url = GISTS_API + `/gists/{self.id}`,
		Method = "PATCH",
		Headers = {
			["Accept"] = "application/vnd.github+json",
			["Authorization"] = `Bearer {self.secret}`,
		},
		Body = encode({
			description = "Created by Gists.lua",
			files = files,
		}),
	}

	local res = handleRequest(req)
	if res.Success and res.Body then
		local f = res.Body.files
		self._URLS = {}
		for k, v in pairs(f) do
			self._URLS[k] = v["raw_url"]
		end
		return nil
	else
		error(`Request failed at Gist:Write()`)
	end
end

type IGistManager = {
	_GISTS: { IGist },
	CreateGist: (self: IGistManager, name: string) -> IGist,
	DeleteGist: (self: IGistManager, name: string) -> nil,
	FetchGist: (self: IGistManager, name: string) -> IGist?,
	new: (secret: string) -> IGistManager,
}

local GistManager: IGistManager = {} :: IGistManager

function GistManager.new(secret: string) : IGistManager
	local self = setmetatable({}, GistManager)

	self.secret = secret
	self._GISTS = {}

	return self
end

function GistManager:CreateGist(name: string) : IGist
	local gist = Gist.new(self.secret, name)
	table.insert(self._GISTS, gist)
	return gist
end

function GistManager:DeleteGist(name: string) : nil
	local gist = self:FetchGist(name)
	local index = table.find(self._GISTS, gist)
	if gist and index > 0 then
		gist:_Purge()
		table.remove(self._GISTS, index)
		setmetatable(gist, nil)
		return nil
	else
		error(`Cannot delete nonexistant Gist "{name}" with index {index}`)
	end
end

function GistManager:FetchGist(name: string) : IGist?
	for _, g in ipairs(self._GISTS) do
		if g.name == name then
			return g
		end
	end
	--TODO: Fetch from API
	return nil
end
