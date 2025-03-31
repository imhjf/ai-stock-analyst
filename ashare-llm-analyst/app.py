from fastapi import FastAPI, Query, HTTPException, BackgroundTasks
from fastapi.staticfiles import StaticFiles
import uuid
import os
from main import StockAnalyzer
import logging


app = FastAPI(title="Stock Analysis API")

# 挂载静态文件目录
app.mount("/result", StaticFiles(directory="public"), name="public")

# 存储流水号对应的状态
task_status = {}
filepath = 'public'


@app.get("/version")
async def start():
    return '1.0.0'


def run_analysis_task(sd: str, name: str, code: str):
    try:
        task_status[sd]['status'] = 'running'
        analyzer = StockAnalyzer({name: code})
        html_path = f'{filepath}/{sd}.html'
        analyzer.run_analysis(output_path=html_path)        
        task_status[sd]['status'] = 'completed'
    except Exception as e:
        logging.exception(e)
        task_status[sd]['status'] = 'failed'
        task_status[sd]['error'] = str(e)


@app.get("/start")
async def start(
    background_tasks: BackgroundTasks,
    name: str = Query(..., description="股票名称"), 
    code: str = Query(..., description="股票代码")
):
    if not name or not code:
        raise HTTPException(status_code=400, detail="Missing name or code parameter")
    # 生成流水号
    sd = str(uuid.uuid4()).replace('-', '')
    # 存储初始状态
    task_status[sd] = {
        'name': name,
        'code': code,
        'status': 'pending',
    }
    # 添加到后台任务
    background_tasks.add_task(run_analysis_task, sd, name, code)
    return sd


@app.get("/process")
async def process(sd: str = Query(..., description="流水号，多个用逗号分隔")):
    sd_list = sd.split(',')
    if not sd_list:
        raise HTTPException(status_code=400, detail="Missing sd parameter")
    results = []
    for sd_item in sd_list:
        if sd_item in task_status:
            status = task_status[sd_item]['status']
            # 状态映射：pending/running -> 0, completed -> 1, failed -> -1
            result = '1' if status == 'completed' else ('-1' if status == 'failed' else '0')
            results.append(result)
        else:
            results.append('-1')
    return ','.join(results)


@app.delete("/delete")
async def delete(sd: str = Query(..., description="流水号，多个用逗号分隔")):
    sd_list = sd.split(',')
    if not sd_list:
        raise HTTPException(status_code=400, detail="Missing sd parameter")
    for sd_item in sd_list:
        if sd_item in task_status:
            del task_status[sd_item]
        os.remove(f'{filepath}/{sd_item}.html')
    return 'success'


if __name__ == "__main__":
    # 确保public目录存在
    os.makedirs("public", exist_ok=True)
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=6000)
