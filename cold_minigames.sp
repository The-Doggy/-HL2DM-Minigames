/* Had a random desire to make tag in sourcepawn so here we are, may add other minigames in the future like hide n seek and shit like that */

#include <sdktools>
#include <sdkhooks>
#include <morecolors>
#include <smlib>
#include <cold_minigames>

#pragma newdecls required
#pragma semicolon 1

#define CMDTAG			"{dodgerblue}[Minigames]{default}"
#define CONSOLETAG 		"[Minigames]"

public Plugin myinfo = 
{
	name = "[HL2:DM] Minigames",
	author = "The Doggy",
	description = "Hopefully a bunch of fun minigames to mess around with eventually",
	version = "0.2.5",
	url = "coldcommunity.com"
};

bool g_bLate;
Handle g_HUD;
Handle g_HUDDistance;
int g_iCheatTimes[MAXPLAYERS + 1];
char g_sBuildPath[PLATFORM_MAX_PATH];

enum struct TagData
{
	bool Created; // Game has been created
	bool Started; // Game has been started
	float TimeRemaining; // Amount of time left until runners win
	ArrayList TotalPlayers; // Total amount of players currently playing
	Handle BeepTimer; // Timer for beep runners
	Handle EndTimer; // Timer for game end

	void Reset(bool deleteEnd = true)
	{
		this.Created = false;
		this.Started = false;
		this.TimeRemaining = 0.0;
		this.TotalPlayers.Clear();
		delete this.BeepTimer;
		if(deleteEnd)
			delete this.EndTimer;
	}
}

enum struct PlayerTagData
{
	bool Leader; // Player who created game
	bool Tagger; // Player who is currently "IT"
	bool Runner; // Player who is not currently "IT"
	bool Beep; // Beep player
	int Tags; // The amount of players a player has tagged
	float RunnerTime; // The amount of time a player is a runner for

	void Reset()
	{
		this.Leader = false;
		this.Tagger = false;
		this.Runner = false;
		this.Beep = false;
		this.Tags = 0;
		this.RunnerTime = 0.0;
	}

	bool IsPlaying()
	{
		if(this.Leader || this.Tagger || this.Runner) return true;
		return false;
	}
}

TagData g_Tag;
PlayerTagData g_TagPlayers[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("IsClientInMinigame", Native_InMinigame);
	g_bLate = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// Load translations
	LoadTranslations("common.phrases");

	// Register commands
	RegConsoleCmd("sm_tag", Command_Tag, "Creates a game of tag");
	RegConsoleCmd("sm_join", Command_JoinTag, "Joins a game of tag");
	RegConsoleCmd("sm_start", Command_StartTag, "Starts a game of tag");

	RegAdminCmd("sm_tagunban", Command_UnbanFromTag, ADMFLAG_CUSTOM5, "Unbans a player from tag");
	RegAdminCmd("sm_tagban", Command_BanFromTag, ADMFLAG_CUSTOM5, "Bans a player from tag");

	// Command Listeners
	AddCommandListener(Listener_BlockKill, "kill");
	AddCommandListener(Listener_BlockCommands, "sm_items");
	AddCommandListener(Listener_BlockCommands, "sm_gang");
	AddCommandListener(Listener_BlockCommands, "sm_switch");

	// Late Load
	if(g_bLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
				OnClientPutInServer(i);
		}
	}

	// HUD Timer
	CreateTimer(1.0, GlobalSecondTimer, _, TIMER_REPEAT);

	// Hook spawn
	HookEvent("player_spawn", Event_PlayerSpawn);

	// HUD Sync
	g_HUD = CreateHudSynchronizer();
	g_HUDDistance = CreateHudSynchronizer();

	// Build path 
	BuildPath(Path_SM, g_sBuildPath, sizeof(g_sBuildPath), "configs/minigame_bans.txt");
}

public void OnMapStart()
{
	PrecacheSound("buttons/blip1.wav", true);
}

public void OnClientPutInServer(int Client)
{
	SDKHook(Client, SDKHook_OnTakeDamage, OnTakeDamage);
	//	SDKHook(Client, SDKHook_WeaponCanSwitchTo, OnWeaponSwitch);
	g_TagPlayers[Client].Reset();
	g_iCheatTimes[Client] = 0;
}

public void OnClientDisconnect(int Client)
{
	g_iCheatTimes[Client] = 0;

	if(g_TagPlayers[Client].Leader && g_Tag.Created && !g_Tag.Started)
	{
		CPrintToTagAll("%s %N has left the game, Tag cancelled...", CMDTAG, Client);
		g_Tag.Reset();
		ResetTagModifiers();
		ResetTagPlayers();
		return;
	}

	g_TagPlayers[Client].Reset();

	if(g_Tag.TotalPlayers != null)
	{
		int index = g_Tag.TotalPlayers.FindValue(Client);
		if(index != -1)
		{
			g_Tag.TotalPlayers.Erase(index);

			if(g_Tag.TotalPlayers.Length <= 1)
			{
				CPrintToTagAll("%s Not enough players to continue, cancelling game...", CMDTAG);
				g_Tag.Reset();
				ResetTagModifiers();
				ResetTagPlayers();
			}
		}
	}

	int taggerNum = GetTaggerCount();
	if(taggerNum == 0 && g_Tag.Started)
	{
		CPrintToTagAll("%s All taggers have left the game, picking new tagger...", CMDTAG);

		int tagger = GetRandomTagPlayer();

		SetTagger(tagger);
		CPrintToTagAll("%s %N is the new tagger!", CMDTAG, tagger);
	}
}

void RemoveFromTag(int Client)
{
	if(g_TagPlayers[Client].Leader && g_Tag.Created && !g_Tag.Started)
	{
		CPrintToTagAll("%s %N has left the game, Tag cancelled...", CMDTAG, Client);
		g_Tag.Reset();
		ResetTagModifiers();
		ResetTagPlayers();
		return;
	}

	g_TagPlayers[Client].Reset();

	if(g_Tag.TotalPlayers != null)
	{
		int index = g_Tag.TotalPlayers.FindValue(Client);
		if(index != -1)
		{
			g_Tag.TotalPlayers.Erase(index);

			if(g_Tag.TotalPlayers.Length <= 1)
			{
				CPrintToTagAll("%s Not enough players to continue, cancelling game...", CMDTAG);
				g_Tag.Reset();
				ResetTagModifiers();
				ResetTagPlayers();
			}
		}
	}

	int taggerNum = GetTaggerCount();
	if(taggerNum == 0 && g_Tag.Started)
	{
		CPrintToTagAll("%s All taggers have left the game, picking new tagger...", CMDTAG);

		int tagger = GetRandomTagPlayer();

		SetTagger(tagger);
		CPrintToTagAll("%s %N is the new tagger!", CMDTAG, tagger);
	}
}

public Action Listener_BlockKill(int Client, const char[] command, int argc)
{
	if(!IsValidClient(Client)) return Plugin_Continue;

	if(g_Tag.Started && g_TagPlayers[Client].IsPlaying())
	{
		CPrintToChat(Client, "%s No Cheating!", CMDTAG);
		g_iCheatTimes[Client]++;

		if(g_iCheatTimes[Client] >= 5)
		{
			KeyValues kv = new KeyValues("BannedPlayers");
			kv.ImportFromFile(g_sBuildPath);

			char sSteam[64];
			if(!GetClientAuthId(Client, AuthId_SteamID64, sSteam, sizeof(sSteam)))
			{
				LogError("Failed to get client %N's steamid", Client);
				delete kv;
				return Plugin_Stop;
			}

			kv.JumpToKey(sSteam, true);
			kv.SetString(NULL_STRING, "yeet");
			kv.Rewind();

			if(!kv.ExportToFile(g_sBuildPath))
				LogError("Failed to export keyvalues to file %s", g_sBuildPath);
			else
			{
				CPrintToChat(Client, "%s You have been banned from playing tag for cheating.", CMDTAG);
				g_TagPlayers[Client].Reset();

				int index = g_Tag.TotalPlayers.FindValue(Client);
				if(index != -1)
					g_Tag.TotalPlayers.Erase(index);

				if(g_Tag.TotalPlayers.Length <= 1)
				{
					CPrintToTagAll("%s Not enough players to continue, cancelling game...", CMDTAG);
					g_Tag.Reset();
					ResetTagModifiers();
					ResetTagPlayers();
				}
			}

			delete kv;
		}

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Command_UnbanFromTag(int Client, int args)
{
	if(args != 1)
	{
		CReplyToCommand(Client, "%s Invalid Syntax. Usage: sm_tagunban <player>", CMDTAG);
		return Plugin_Handled;
	}

	char arg[MAX_NAME_LENGTH];
	GetCmdArg(1, arg, sizeof(arg));

	int target = FindTarget(Client, arg);
	if(target == -1) return Plugin_Handled;

	KeyValues kv = new KeyValues("BannedPlayers");
	if(!kv.ImportFromFile(g_sBuildPath))
	{
		CReplyToCommand(Client, "%s No banned players exist.", CMDTAG);
		delete kv;
		return Plugin_Handled;
	}

	char sSteam[64];
	if(!GetClientAuthId(target, AuthId_SteamID64, sSteam, sizeof(sSteam)))
	{
		LogError("Failed to get client %N's steamid", target);
		CReplyToCommand(Client, "%s An error occurred, please try again later.", CMDTAG);
		delete kv;
		return Plugin_Handled;
	}

	if(!kv.JumpToKey(sSteam))
	{
		CReplyToCommand(Client, "%s %N is not banned.", CMDTAG, target);
		delete kv;
		return Plugin_Handled;
	}

	if(!kv.DeleteThis())
	{
		CReplyToCommand(Client, "%s Failed to unban player %N", CMDTAG, target);
		delete kv;
		return Plugin_Handled;
	}

	kv.Rewind();

	if(!kv.ExportToFile(g_sBuildPath))
	{
		LogError("Failed to export keyvalues to file %s", g_sBuildPath);
		CReplyToCommand(Client, "%s Failed to unban player %N", target);
		delete kv;
		return Plugin_Handled;
	}

	CReplyToCommand(Client, "%s %N has been unbanned from playing tag.", CMDTAG, target);
	CPrintToChat(target, "%s You have been unbanned from playing tag.", CMDTAG);
	delete kv;
	return Plugin_Handled;
}

public Action Command_BanFromTag(int Client, int args)
{
	if(args != 1)
	{
		CReplyToCommand(Client, "%s Invalid Syntax. Usage: sm_tagban <player>");
		return Plugin_Handled;
	}

	char arg[MAX_NAME_LENGTH];
	GetCmdArg(1, arg, sizeof(arg));

	int target = FindTarget(Client, arg);
	if(target == -1) return Plugin_Handled;

	KeyValues kv = new KeyValues("BannedPlayers");
	kv.ImportFromFile(g_sBuildPath);

	char sSteam[64];
	if(!GetClientAuthId(target, AuthId_SteamID64, sSteam, sizeof(sSteam)))
	{
		LogError("Failed to get client %N's steamid", target);
		CReplyToCommand(Client, "%s An error occurred, please try again later.", CMDTAG);
		delete kv;
		return Plugin_Handled;
	}

	if(!kv.JumpToKey(sSteam, true))
	{
		CReplyToCommand(Client, "%s Failed to ban player %N", CMDTAG, target);
		delete kv;
		return Plugin_Handled;
	}

	kv.SetString(NULL_STRING, "yeet");

	kv.Rewind();

	if(!kv.ExportToFile(g_sBuildPath))
	{
		LogError("Failed to export keyvalues to file %s", g_sBuildPath);
		CReplyToCommand(Client, "%s Failed to ban player %N", CMDTAG, target);
		delete kv;
		return Plugin_Handled;
	}

	CReplyToCommand(Client, "%s %N has been banned from playing tag.", CMDTAG, target);
	CPrintToChat(target, "%s You have been banned from playing tag.", CMDTAG);

	g_TagPlayers[target].Reset();

	int index = g_Tag.TotalPlayers.FindValue(target);
	if(index != -1)
		g_Tag.TotalPlayers.Erase(index);

	if(g_Tag.TotalPlayers.Length <= 1)
	{
		CPrintToTagAll("%s Not enough players to continue, cancelling game...", CMDTAG);
		g_Tag.Reset();
		ResetTagModifiers();
		ResetTagPlayers();
	}


	delete kv;
	return Plugin_Handled;
}

public Action Listener_BlockCommands(int Client, const char[] command, int argc)
{
	if(!IsValidClient(Client)) return Plugin_Continue;

	if(g_Tag.Started && g_TagPlayers[Client].IsPlaying())
	{
		CPrintToChat(Client, "%s No Cheating!", CMDTAG);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(DelaySpawn, event.GetInt("userid"));
}

void DelaySpawn(int userid)
{
	int Client = GetClientOfUserId(userid);
	if(!IsValidClient(Client)) return;

	if(g_Tag.Started)
	{
		if(g_TagPlayers[Client].Runner)
		{
			SetEntProp(Client, Prop_Data, "m_CollisionGroup", 2);
			SetEntityRenderColor(Client, 255, 0, 183, 255);
		}
		else if(g_TagPlayers[Client].Tagger)
			SetTagger(Client);
	}
}

bool IsCuffed(int Client)
{
	char isCuffed[16];
	GetEntPropString(Client, Prop_Data, "m_iName", isCuffed, sizeof(isCuffed));
	return StrEqual(isCuffed, "cuffed");
}

public Action GlobalSecondTimer(Handle timer)
{
	// Players Joined HUD Text
	if(g_Tag.Created && !g_Tag.Started)
	{
		SetHudTextParams(-1.0, 0.2, 1.0, 255, 255, 255, 255);

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || !g_TagPlayers[i].IsPlaying()) continue;

			if(IsCuffed(i))
			{
				RemoveFromTag(i);
				continue;
			}

			ShowSyncHudText(i, g_HUD, "Players Joined: %i", g_Tag.TotalPlayers.Length);
		}
	}
	else if(g_Tag.Started)
	{
		int runnerNum = GetRunnerCount();
		ArrayList distance = new ArrayList();

		for(int i = 1; i <= MaxClients; i++)
		{
			// Main tag HUD
			if(!IsClientInGame(i) || !g_TagPlayers[i].IsPlaying()) continue;

			if(IsCuffed(i))
			{
				RemoveFromTag(i);
				continue;
			}

			SetHudTextParams(-1.0, 0.7, 1.0, 255, 255, 255, 255);
			ShowSyncHudText(i, g_HUD, "Runners Remaining: %i\nTime Remaining: %i", runnerNum, RoundFloat(g_Tag.TimeRemaining));

			// Tagger HUD
			if(g_TagPlayers[i].Tagger)
			{
				// Set tagger colour
				SetEntityRenderColor(i, 0, 51, 255);

				// Give stunstick if dont have
				if(!Client_HasWeapon(i, "weapon_stunstick"))
					GivePlayerItem(i, "weapon_stunstick");

				// Setup distance vars
				float pos[3], vec[3];

				// Get tagger position
				GetClientAbsOrigin(i, pos);

				for(int j = 1; j <= MaxClients; j++)
				{
					if(!IsClientInGame(j) || !g_TagPlayers[j].Runner) continue;

					// Get runner position
					GetClientAbsOrigin(j, vec);

					// Calculate distance
					distance.Push(GetVectorDistance(pos, vec));
				}

				// Sort distances
				distance.Sort(Sort_Ascending, Sort_Float);

				SetHudTextParams(-1.0, 0.6, 1.0, 255, 255, 255, 255);
				ShowSyncHudText(i, g_HUDDistance, "Distance to closest runner: %i", RoundFloat(distance.Get(0)));
				distance.Clear();
			}
			
			// Runner beep and colour
			if(g_TagPlayers[i].Runner)
			{
				SetEntityRenderColor(i, 255, 0, 183, 255);
				
				if(g_TagPlayers[i].Beep)
				{
					float vec[3];

					GetClientEyePosition(i, vec);
					EmitAmbientSound("buttons/blip1.wav", vec, i, SNDLEVEL_NORMAL);
				}
			}
		}
		delete distance;
		g_Tag.TimeRemaining--;
	}
	return Plugin_Continue;
}

public Action Command_Tag(int Client, int iArgs)
{
	if(Client == 0)
	{
		CReplyToCommand(Client, "%s This command cannot be run from the server console.", CONSOLETAG);
		return Plugin_Handled;
	}

	if(g_Tag.Created || g_Tag.Started)
	{
		CReplyToCommand(Client, "%s There is already a game of tag in progress, please wait for it to finish before starting a new one.", CMDTAG);
		return Plugin_Handled;
	}

	if(IsClientBanned(Client))
	{
		CReplyToCommand(Client, "%s You are banned from playing tag!", CMDTAG);
		return Plugin_Handled;
	}

	if(g_Tag.TotalPlayers == null)
		g_Tag.TotalPlayers = new ArrayList();

	g_Tag.Created = true;
	g_Tag.TotalPlayers.Push(Client);
	g_TagPlayers[Client].Leader = true;

	CReplyToCommand(Client, "%s Game has been created, type {green}!start{default} to start or wait for more players to join.", CMDTAG);
	CPrintToChatAll("%s %N has created a game of Tag! Type {green}!join{default} to join!", CMDTAG, Client);
	CreateTimer(300.0, Timer_StartTag, GetClientUserId(Client));
	return Plugin_Handled;
}

public Action Command_JoinTag(int Client, int args)
{
	if(Client == 0)
	{
		CReplyToCommand(Client, "%s This command cannot be run from the server console.", CONSOLETAG);
		return Plugin_Handled;
	}

	if(g_Tag.Started)
	{
		CReplyToCommand(Client, "%s There is already a game of Tag running, please wait for a new game to start.", CMDTAG);
		return Plugin_Handled;
	}

	if(!g_Tag.Created)
	{
		CReplyToCommand(Client, "%s There are no games of Tag currently running.", CMDTAG);
		return Plugin_Handled;
	}

	if(g_Tag.TotalPlayers.FindValue(Client) != -1)
	{
		CReplyToCommand(Client, "%s You've already joined this game of Tag!", CMDTAG);
		return Plugin_Handled;
	}

	if(IsClientBanned(Client))
	{
		CReplyToCommand(Client, "%s You are banned from playing tag!", CMDTAG);
		return Plugin_Handled;
	}

	// Push player into totalplayers list
	g_Tag.TotalPlayers.Push(Client);
	g_TagPlayers[Client].Runner = true;

	// Get tag leader
	int leader = GetTagLeader();

	// It shouldn't be possible for this to be -1 at this point but just in case
	if(leader != -1)
	{
		CPrintToChat(Client, "%s You have joined %N's game of Tag!", CMDTAG, leader);
		CPrintToTagLeader("%s %N has joined your game of Tag!", CMDTAG, Client);
	}
	else
		CPrintToChat(Client, "%s You have joined the game of Tag!", CMDTAG);

	return Plugin_Handled;
}

public Action Command_StartTag(int Client, int args)
{
	if(Client == 0)
	{
		CReplyToCommand(Client, "%s This command cannot be run from the server console.", CMDTAG);
		return Plugin_Handled;
	}

	if(!g_Tag.Created || g_Tag.Started)
	{
		CReplyToCommand(Client, "%s There are no games of Tag to be started.", CMDTAG);
		return Plugin_Handled;
	}

	if(!g_TagPlayers[Client].Leader)
	{
		CReplyToCommand(Client, "%s You are not the Tag leader!", CMDTAG);
		return Plugin_Handled;
	}

	if(g_Tag.TotalPlayers.Length <= 1)
	{
		CReplyToCommand(Client, "%s There are not enough players to start the game.", CMDTAG);
		return Plugin_Handled;
	}

	CReplyToCommand(Client, "%s Your game of Tag will start shortly...", CMDTAG);
	StartGame();
	return Plugin_Handled;
}

public Action Timer_StartTag(Handle timer, int userid)
{
	if(g_Tag.Started) return Plugin_Stop;

	int Client = GetClientOfUserId(userid);
	if(!IsValidClient(Client))
	{
		CPrintToTagAll("%s Tag leader has left the game. Tag ended.", CMDTAG);

		g_Tag.Reset();
		ResetTagModifiers();
		ResetTagPlayers();
		return Plugin_Stop;
	}

	if(Client != GetTagLeader())
		return Plugin_Stop;

	if(!g_Tag.Created)
	{
		CPrintToTagAll("%s Tag game is no longer valid, cancelling game...", CMDTAG);

		g_Tag.Reset();
		ResetTagModifiers();
		ResetTagPlayers();
		return Plugin_Stop;
	}

	if(g_Tag.TotalPlayers.Length <= 1)
	{
		CPrintToChat(Client, "%s No players have joined your game of Tag. Cancelling game...", CMDTAG);

		g_Tag.Reset();
		ResetTagModifiers();
		ResetTagPlayers();
		return Plugin_Stop;
	}

	CPrintToChat(Client, "%s Your game of Tag will start shortly...", CMDTAG);
	StartGame();
	return Plugin_Stop;
}

void StartGame()
{
	CPrintToTagAll("%s Game starting...", CMDTAG);

	float pos[3];
	int leader = GetTagLeader();
	GetClientAbsOrigin(leader, pos);

	int[] clients = new int[g_Tag.TotalPlayers.Length];
	int num;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !g_TagPlayers[i].IsPlaying()) continue;

		clients[num++] = i; // For selecting tagger
		SetEntProp(i, Prop_Data, "m_CollisionGroup", 2);
		SetEntityRenderColor(i, 255, 0, 183, 255);
		g_TagPlayers[i].Runner = true;
		TeleportEntity(i, pos, NULL_VECTOR, NULL_VECTOR);
	}

	// Pick tagger randomly
	int tagger = clients[GetRandomInt(0, g_Tag.TotalPlayers.Length - 1)];
	SetEntityMoveType(tagger, MOVETYPE_NONE);

	// Fade tagger
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("Fade", tagger));
	bf.WriteShort(1000000000);
	bf.WriteShort(1000000000);
	bf.WriteShort(FFADE_PURGE);
	bf.WriteByte(0);
	bf.WriteByte(0);
	bf.WriteByte(0);
	bf.WriteByte(255);
	EndMessage();

	SetTagger(tagger);

	CPrintToTagAll("%s %N is {green}IT!{default} All other players have 10 seconds to run before %N is able to chase!", CMDTAG, tagger, tagger);

	g_Tag.Created = false;
	g_Tag.Started = true;

	CreateTimer(10.0, Timer_ReleaseTagger, GetClientUserId(tagger));

	g_Tag.TimeRemaining = 600.0;
	g_Tag.EndTimer = CreateTimer(g_Tag.TimeRemaining, Timer_EndGame);
	g_Tag.BeepTimer = CreateTimer(g_Tag.TimeRemaining / 2, Timer_BeepRunners);
}

public Action Timer_ReleaseTagger(Handle timer, int userid)
{
	int Client = GetClientOfUserId(userid);
	if(!IsValidClient(Client))
	{
		CPrintToTagAll("%s Tagger has left the game, picking new tagger...", CMDTAG);

		int tagger = GetRandomTagPlayer();

		SetTagger(tagger);
		CPrintToTagAll("%s %N is the new tagger!", CMDTAG, tagger);
		return Plugin_Stop;
	}

	// UNFade tagger
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("Fade", Client));
	bf.WriteShort(1000000000);
	bf.WriteShort(1000000000);
	bf.WriteShort(FFADE_PURGE);
	bf.WriteByte(0);
	bf.WriteByte(0);
	bf.WriteByte(0);
	bf.WriteByte(0);
	EndMessage();

	SetEntityMoveType(Client, MOVETYPE_WALK);
	CPrintToTagAll("%s %N is now able to chase!", CMDTAG, Client);
	return Plugin_Stop;
}

public Action Timer_EndGame(Handle timer)
{
	int runnerNum = GetRunnerCount();
	if(runnerNum >= 1)
		CPrintToTagAll("%s Time has run out! Runners win!", CMDTAG);

	g_Tag.Reset(false);
	ResetTagModifiers();
	ResetTagPlayers();

	g_Tag.EndTimer = null;
	return Plugin_Stop;
}

public Action Timer_BeepRunners(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !g_TagPlayers[i].Runner) continue;
		g_TagPlayers[i].Beep = true;
	}
	CPrintToTagAll("%s Runners are now beeping!", CMDTAG);

	g_Tag.BeepTimer = null;
	return Plugin_Stop;
}

//	public Action OnWeaponSwitch(int Client, int weapon)
//	{
//		if(!g_Tag.Started) return Plugin_Continue;
//		if(!g_TagPlayers[Client].Tagger) return Plugin_Continue;

//		char class[64];
//		GetEntityClassname(weapon, class, sizeof(class));

//		if(!StrEqual(class, "weapon_stunstick"))
//			return Plugin_Handled;

//		return Plugin_Continue;
//	}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
	if(!IsValidClient(victim) || !IsValidClient(attacker)) return Plugin_Continue;
	if(!g_Tag.Started) return Plugin_Continue;
	if(!g_TagPlayers[attacker].IsPlaying() && !g_TagPlayers[victim].IsPlaying()) return Plugin_Continue;

	char class[64];
	Client_GetActiveWeaponName(attacker, class, sizeof(class));

	if(g_TagPlayers[victim].Runner && g_TagPlayers[attacker].Tagger && StrEqual(class, "weapon_stunstick") && g_Tag.TimeRemaining < 590.0)
	{
		CPrintToChat(victim, "%s %N tagged you!", CMDTAG, attacker);
		CPrintToChat(attacker, "%s You tagged %N!", CMDTAG, victim);
		CPrintToTagAll("%s %N tagged %N!", CMDTAG, attacker, victim);

		SetTagger(victim);

		int runnerNum = GetRunnerCount();
		if(runnerNum == 0)
		{
			CPrintToTagAll("%s All runners have been caught! Taggers win!", CMDTAG);
	
			g_Tag.Reset();
			ResetTagModifiers();
			ResetTagPlayers();
		}
	}

	damage = 0.0;
	return Plugin_Changed;
}

stock void ResetTagModifiers()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !g_TagPlayers[i].IsPlaying()) continue;
		SetEntityRenderColor(i, 255, 255, 255);
		SetEntProp(i, Prop_Data, "m_CollisionGroup", 5);
	}
}

stock void SetTagger(int Client)
{
	g_TagPlayers[Client].Tagger = true;
	g_TagPlayers[Client].Runner = false;
	g_TagPlayers[Client].Beep = false;
	SetEntityRenderColor(Client, 0, 51, 255);
	if(IsPlayerAlive(Client))
		GivePlayerItem(Client, "weapon_stunstick");
	CPrintToChat(Client, "%s You've become a tagger!", CMDTAG);
}

stock void ResetTagPlayers()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		g_TagPlayers[i].Reset();
	}
}

stock int GetRandomTagPlayer()
{
	int player;
	int count;
	do
	{
		if(count >= 1000) return -1;

		player = GetRandomInt(1, MaxClients);

		count++;
	} while(!IsValidClient(player) || !g_TagPlayers[player].IsPlaying());
	return player;
}

stock int GetRunnerCount()
{
	int count;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && g_TagPlayers[i].Runner)
			count++;
	}
	return count;
}

stock int GetTaggerCount()
{
	int count;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && g_TagPlayers[i].Tagger)
			count++;
	}
	return count;
}

stock int GetTagLeader()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !g_TagPlayers[i].Leader) continue;
		return i;
	}
	return -1;
}

stock bool IsClientBanned(int Client)
{
	if(!IsValidClient(Client)) return false;

	KeyValues kv = new KeyValues("BannedPlayers");
	if(!kv.ImportFromFile(g_sBuildPath))
	{
		LogError("Failed to load banned players from %s", g_sBuildPath);
		delete kv;
		return false;
	}

	char sSteam[64];
	if(!GetClientAuthId(Client, AuthId_SteamID64, sSteam, sizeof(sSteam)))
	{
		LogError("Failed to get client %N's steamid", Client);
		delete kv;
		return false;
	}

	if(!kv.JumpToKey(sSteam))
	{
		delete kv;
		return false;
	}
	
	return true;
}

stock void CPrintToTagLeader(const char[] format, any ...)
{
	char sMessage[1024];
	VFormat(sMessage, sizeof(sMessage), format, 2);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !g_TagPlayers[i].Leader) continue;

		SetGlobalTransTarget(i);
		CPrintToChat(i, "%s", sMessage);
	}
}

stock void CPrintToTagAll(const char[] format, any ...)
{
	char sMessage[1024];
	VFormat(sMessage, sizeof(sMessage), format, 2);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !g_TagPlayers[i].IsPlaying()) continue;

		SetGlobalTransTarget(i);
		CPrintToChat(i, "%s", sMessage);
	}
}

stock bool IsValidClient(int client)
{
	return client >= 1 && 
	client <= MaxClients && 
	IsClientConnected(client) && 
	IsClientAuthorized(client) && 
	IsClientInGame(client);
}

public any Native_InMinigame(Handle plugin, int numParams)
{
	int Client = GetNativeCell(1);
	if(!IsValidClient(Client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %i", Client);
		return false;
	}

	return g_TagPlayers[Client].IsPlaying();
}