package com.androlua;

import android.content.*;
import android.content.res.*;
import com.luajava.*;
import java.io.*;

public class LuaAssetLoader extends JavaFunction
{

	private LuaState L;

	private Context mContext;

	public LuaAssetLoader(LuaContext luaContext,LuaState L)
	{
		super(L);
		this.L = L;
		mContext=luaContext.getContext();
	}

	@Override
	public int execute() throws LuaException
	{
		String name = L.toString(-1);
		name = name.replace('.', '/') + ".lua";
		try
		{
			byte[] bytes = readAsset(name);
			int ok=L.LloadBuffer(bytes, name);
			if (ok != 0)
				L.pushString("\n\t" + L.toString(-1));
			return 1;
		}
		catch (IOException e)
		{
			L.pushString("\n\tno file \'/assets/" + name + "\'");
			return 1;
		}
	}
	public byte[] readAsset(String name) throws IOException 
	{
		return LuaUtil.readAsset(mContext, name);
	}
}
