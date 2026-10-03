package com.androlua;

import android.view.View;
import android.widget.ArrayPageAdapter;

/**
 * 项目自带 PageView 用的分页适配器：继承 android.widget.ArrayPageAdapter
 * （也就是 android.widget.BasePageAdapter 这一系），额外支持每页标题。
 *
 * 为什么需要它：PageView.setAdapter 只接受 android.widget.BasePageAdapter 的子类，
 * 而 androidx 的 PagerAdapter（LuaPagerAdapter）喂不进去；反过来也一样。
 * BasePageAdapter 本身已经声明了 getPageTitle()，这里把它实现出来。
 */
public class PageViewAdapter extends ArrayPageAdapter {

    private final String[] mTitles;

    public PageViewAdapter(View[] views) {
        super(views);
        mTitles = null;
    }

    public PageViewAdapter(View[] views, String[] titles) {
        super(views);
        mTitles = titles;
    }

    @Override
    public CharSequence getPageTitle(int position) {
        if (mTitles == null || position < 0 || position >= mTitles.length) {
            return null;
        }
        return mTitles[position];
    }
}
