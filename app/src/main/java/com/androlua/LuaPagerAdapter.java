package com.androlua;

import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.viewpager.widget.PagerAdapter;

/**
 * ViewPager 适配器：直接拿一组已经建好的 View 当页面，可选带每页标题。
 *
 * 之所以要写在 Java 侧：PagerAdapter 是抽象类，LuaJava 的 proxy 只能对付接口，
 * Lua 端写不出来。loadlayout 的 pages / pagesWithTitle 用它。
 */
public class LuaPagerAdapter extends PagerAdapter {

    private final View[] mViews;
    private final String[] mTitles;

    public LuaPagerAdapter(View[] views) {
        this(views, null);
    }

    public LuaPagerAdapter(View[] views, String[] titles) {
        mViews = views;
        mTitles = titles;
    }

    @Override
    public int getCount() {
        return mViews == null ? 0 : mViews.length;
    }

    @Override
    public boolean isViewFromObject(@NonNull View view, @NonNull Object object) {
        return view == object;
    }

    @NonNull
    @Override
    public Object instantiateItem(@NonNull ViewGroup container, int position) {
        View page = mViews[position];
        if (page.getParent() != null) {
            ((ViewGroup) page.getParent()).removeView(page);
        }
        container.addView(page);
        return page;
    }

    @Override
    public void destroyItem(@NonNull ViewGroup container, int position, @NonNull Object object) {
        container.removeView((View) object);
    }

    @Override
    public CharSequence getPageTitle(int position) {
        if (mTitles == null || position < 0 || position >= mTitles.length) {
            return null;
        }
        return mTitles[position];
    }
}
